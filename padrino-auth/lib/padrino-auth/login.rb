require 'ostruct'
require 'padrino-auth/login/controller'

module Padrino
  # Padrino authentication module.
  module Login
    class << self
      def set_defaults(app)
        app.set :credentials_accessor, :credentials unless app.respond_to?(:credentials_accessor)
        app.set :session_id, app.app_name.to_sym unless app.respond_to?(:session_id)
        app.set :login_url, '/login'             unless app.respond_to?(:login_url)
        app.set :login_model, :account           unless app.respond_to?(:login_model)
        app.disable :login_bypass                unless app.respond_to?(:login_bypass)
        if app.respond_to?(:set_access)
          app.set_access(:*, :allow => :*, :with => :login)
        else
          app.set :permissions do
            set_access(:*, :allow => :*, :with => :login)
          end
        end
      end

      def registered(app)
        included(app)
        set_defaults(app)
        app.before do
          log_in if authorization_required?
        end
        app.reset_login!
        app.send :attr_reader, app.credentials_accessor unless app.instance_methods.include?(app.credentials_accessor)
        app.send :attr_writer, app.credentials_accessor unless app.instance_methods.include?(:"#{app.credentials_accessor}=")
      end

      def included(base)
        base.send(:include, InstanceMethods)
        base.extend(ClassMethods)
      end
    end

    module ClassMethods
      def reset_login!
        controller :login do
          include Controller
        end
      end
    end

    module InstanceMethods
      def login_model
        @login_model ||= settings.login_model.to_s.classify.constantize
      end

      def authenticate
        resource = login_model.authenticate(:email => params[:email], :password => params[:password])
        resource ||= login_model.authenticate(:bypass => true) if settings.login_bypass && params[:bypass]
        save_credentials(resource)
      end

      def logged_in?
        !!(send(settings.credentials_accessor) || restore_credentials)
      end

      def unauthorized?
        respond_to?(:authorized?) && !authorized?
      end

      def authorization_required?
        if logged_in?
          if unauthorized?
            # 403 Forbidden, provided credentials were successfully
            # authenticated but the credentials still do not grant
            # the client permission to access the resource
            error 403
          else
            false
          end
        else
          unauthorized?
        end
      end

      def log_in
        login_url = settings.login_url
        if request.env['PATH_INFO'] != login_url
          save_location
          # 302 Found
          redirect url(login_url) 
          # 401 Unauthorized, authentication is required and
          # has not yet been provided
          error 401, '401 Unauthorized'
        end
      end

      def save_credentials(resource)
        session[settings.session_id] = resource.respond_to?(:id) ? resource.id : resource
        send(:"#{settings.credentials_accessor}=", resource)
      end

      def restore_credentials
        resource = login_model.authenticate(:session_id => session[settings.session_id])
        send(:"#{settings.credentials_accessor}=", resource)
      end

      def restore_location
        redirect session.delete(:return_to) || url('/')
      end

      def save_location
        uri = request.env['REQUEST_URI'] || url(request.env['PATH_INFO'])
        return if uri.blank? || uri.match(/\.css$|\.js$|\.png$/)
        session[:return_to] = "#{ENV['RACK_BASE_URI']}#{uri}"
      rescue => e
        fail "saving session[:return_to] failed because of #{e.class}: #{e.message}"
      end
    end
  end
end
