module Bleib
  class Configuration
    class UnsupportedAdapterException < Exception; end
    class DatabaseYmlNotFoundException < Exception; end

    attr_reader :database, :check_database_interval, :check_migrations_interval

    DEFAULT_CHECK_DATABASE_INTERVAL = 5 # Seconds
    DEFAULT_CHECK_MIGRATIONS_INTERVAL = 5 # Seconds

    def self.from_environment
      check_database_interval = interval_or_default(
        ENV['BLEIB_CHECK_DATABASE_INTERVAL'],
        DEFAULT_CHECK_DATABASE_INTERVAL
      )
      check_migrations_interval = interval_or_default(
        ENV['BLEIB_CHECK_MIGRATIONS_INTERVAL'],
        DEFAULT_CHECK_DATABASE_INTERVAL
      )

      database_yml_path = ENV['BLEIB_DATABASE_YML_PATH']
      database_yml_path ||= locate_database_yaml!

      rails_env = ENV['RAILS_ENV'] || 'development'

      new(
        rails_database(database_yml_path, rails_env),
        check_database_interval: check_database_interval.to_i,
        check_migrations_interval: check_migrations_interval.to_i
      )
    end

    def initialize(database_configuration,
                   check_database_interval: DEFAULT_CHECK_DATABASE_INTERVAL,
                   check_migrations_interval: DEFAULT_CHECK_MIGRATIONS_INTERVAL)
      # To be 100% sure which connection the
      # active record pool creates, returns or removes.
      only_one_connection = { 'pool' => 1 }

      @database = database_configuration.merge(only_one_connection)

      @check_database_interval = check_database_interval
      @check_migrations_interval = check_migrations_interval

      check!
    end

    def logger
      return @logger unless @logger.nil?

      @logger = Logger.new(STDOUT)
      @logger.level = if ENV['BLEIB_LOG_LEVEL'] == 'debug'
                        Logger::DEBUG
                      else
                        Logger::INFO
                      end
      @logger
    end

    private

    def self.interval_or_default(string, default)
      given = string.to_i
      given <= 0 ? default : given
    end

    def self.locate_database_yaml!
      possible_location = File.expand_path('config/database.yml')
      return possible_location if File.exist?(possible_location)

      fail DatabaseYmlNotFoundException,
           'Database.yml not found, set' \
           'BLEIB_DATABASE_YML_PATH or execute me' \
           'from the rails root.'
    end

    def self.rails_database(database_yml_path, rails_env)
      contents = File.read(database_yml_path)
      config = YAML.load(ERB.new(contents).result)
      config[rails_env]
    end

    def check!
      # We should add clean rescue statements to
      # `Bleib::Database#database_down?`to support
      # other adapters.
      if @database['adapter'] != 'postgresql'
        fail UnsupportedAdapterException,
             "Unknown database adapter #{@database['adapter']}"
      end
    end
  end
end