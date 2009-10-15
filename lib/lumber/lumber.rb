require "socket"
require "active_support/core_ext/duplicable"
require "active_support/core_ext/class"
require "active_support/core_ext/module"

module Lumber

  # Initializes log4r system.  Needs to happen in
  # config/environment.rb before Rails::Initializer.run
  #
  # Options:
  #
  # * :root - defaults to RAILS_ROOT if defined
  # * :env - defaults to RAILS_ENV if defined
  # * :config_file - defaults to <root>}/config/log4r.yml
  # * :log_file - defaults to <root>}/log/<env>.log
  #
  # All config options get passed through to the log4r
  # configurator for use in defining outputters
  #
  def self.init(opts = {})
    opts[:root] ||= RAILS_ROOT if defined?(RAILS_ROOT)
    opts[:env] ||= RAILS_ENV if defined?(RAILS_ENV)
    opts[:config_file] ||= "#{opts[:root]}/config/log4r.yml"
    opts[:log_file] ||= "#{opts[:root]}/log/#{opts[:env]}.log"
    raise "Lumber.init missing one of :root, :env" unless opts[:root] && opts[:env]

    cfg = Log4r::YamlConfigurator
    opts.each do |k, v|
      cfg[k.to_s] = v
    end
    cfg['hostname'] = Socket.gethostname

    cfg.load_yaml_file(opts[:config_file])

    # Workaround for rails bug: http://dev.rubyonrails.org/ticket/8665
    if defined?(RAILS_DEFAULT_LOGGER)
      Object.send(:remove_const, :RAILS_DEFAULT_LOGGER)
    end
    Object.const_set('RAILS_DEFAULT_LOGGER', Log4r::Logger['rails'])

    @@registered_loggers = {}
    self.register_inheritance_handler()
  end

  # Makes :logger exist independently for subclasses and sets that logger
  # to one that inherits from base_class for each subclass as it is created.
  # This allows you to have a finer level of control over logging, for example,
  # put just a single class, or hierarchy of classes, into debug log level
  #
  # for example:
  #
  #   Lumber.setup_logger_hierarchy("ActiveRecord::Base", "rails::models")
  #
  # causes all models that get created to have a log4r logger named
  # "rails::models::<class_name>".  This class can individually be
  # put into debug log mode in production (see {log4r docs}[http://log4r.sourceforge.net/manual.html]), and log
  # output will include "<class_name>" on every log from this class
  # so that you can tell where a log statement came from
  #
  def self.setup_logger_hierarchy(class_name, class_logger_fullname)
    @@registered_loggers[class_name] = class_logger_fullname
    if Object.const_defined?(class_name)
      Object.const_get(class_name).class_eval do
        class_inheritable_accessor :logger
        self.logger = Log4r::Logger.new(class_logger_fullname)
      end
    end
  end

  private

  # Adds a inheritance handler to Object so we can know to add loggers
  # for classes as they get defined.
  def self.register_inheritance_handler()
    return if defined?(Object.inherited_with_lumber_log4r)
    
    Object.class_eval do
      class << self

        def inherited_with_lumber_log4r(subclass)
          inherited_without_lumber_log4r(subclass)

          # if the new class is in the list that were registered directly,
          # then create their logger attribute directly
          logger_name = @@registered_loggers[subclass.name]
          if logger_name
            subclass.class_eval do
              class_inheritable_accessor :logger
              self.logger = Log4r::Logger.new(logger_name)
            end
          else
            # otherwise, walk up the classes hierarchy till you find a logger
            # that was registered, and use that logger as the parent for the
            # logger of the new class
            parent = subclass.superclass
            while ! parent.nil?
              if defined?(parent.logger) && parent.logger
                parent_is_registered = @@registered_loggers.values.find {|v| parent.logger.fullname.index(v) == 0}
                if parent_is_registered
                  subclass.logger = Log4r::Logger.new("#{parent.logger.fullname}::#{subclass.name}")
                  break
                end
              end
              parent = parent.superclass
            end
          end
        end
        
        alias_method_chain :inherited, :lumber_log4r
      end

    end
  end

end