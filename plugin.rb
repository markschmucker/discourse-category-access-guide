# frozen_string_literal: true

# name: discourse-category-access-guide
# about: A Discourse plugin that displays category-specific access messages, guiding users on how to gain entry based on predefined access rules.
# version: 0.1
# authors: Jahan Gagan
# url: TODO

enabled_site_setting :discourse_category_access_guide_enabled

after_initialize do
  if SiteSetting.discourse_category_access_guide_enabled
    module ::DiscourseCategoryAccessGuide
      class CustomInvalidAccess < StandardError
        attr_reader :custom_message, :custom_message_params, :html_safe
      
        def initialize(msg = nil, opts = {})
          super(msg)
      
          opts ||= {}
      
          @custom_message = opts[:custom_message]
          @custom_message_params = opts[:custom_message_params]
          @html_safe = opts[:html_safe]
        end
      end
      
      # Rescuing the exception globally in ApplicationController
      class ApplicationController < ActionController::Base
        rescue_from ::DiscourseCategoryAccessGuide::CustomInvalidAccess do |e|
        
          opts = {
            custom_message: e.custom_message,
            custom_message_params: e.custom_message_params,
            html_safe: e.html_safe
          }
          rescue_discourse_actions(:custom_invalid_access, 403, opts)
        end          
      end    
    end

    module ::CategoryAccessGuideTopicsController
      def show
        begin
          super
        rescue Discourse::InvalidAccess => e
          topic_id = params[:topic_id].to_i

          if topic_id.blank?
            raise Discourse::InvalidAccess
          end

          topic = Topic.find_by(id: topic_id)

          if topic.nil?
            raise Discourse::InvalidAccess
          end

          category_id = topic.category_id
          category_access_map = JSON.parse(SiteSetting.category_access_map || "{}")

          if category_id.present? && category_access_map.key?(category_id.to_s)
            topic_guide_url = category_access_map[category_id.to_s]
            raise ::DiscourseCategoryAccessGuide::CustomInvalidAccess.new(
              "error_message",
              custom_message: "error_message",
              custom_message_params: { url: topic_guide_url },
              html_safe: true
            )
          end

          raise Discourse::InvalidAccess
        end
      end
    end
    ::TopicsController.prepend CategoryAccessGuideTopicsController

    module ::CustomApplicationControllerPatch
      def self.prepended(base)
        base.rescue_from ::DiscourseCategoryAccessGuide::CustomInvalidAccess do |e|
          opts = {
            custom_message: e.custom_message,
            custom_message_params: e.custom_message_params,
            html_safe: e.html_safe
          }
          rescue_discourse_actions(:custom_invalid_access, 403, opts)
        end
      end
    end
    ::ApplicationController.prepend(CustomApplicationControllerPatch)


    module ::CustomRescueDiscourseActionsPatch
      def rescue_discourse_actions(type, status_code, opts = nil)
        opts ||= {}

        if type != :custom_invalid_access
          super
        else
          show_json_errors =
            (request.format && request.format.json?) || (request.xhr?) ||
              ((params[:external_id] || "").ends_with? ".json")
      
          if type == :not_found && opts[:check_permalinks]
            url = opts[:original_path] || request.fullpath
            permalink = Permalink.find_by_url(url)
      
            # there are some cases where we have a permalink but no url
            # cause category / topic was deleted
            if permalink.present? && permalink.target_url
              # permalink present, redirect to that URL
              redirect_with_client_support permalink.target_url,
                                            status: :moved_permanently,
                                            allow_other_host: true
              return
            end
          end
      
          message = title = nil
          with_resolved_locale(check_current_user: false) do
            if opts[:custom_message]
              title = message = I18n.t(opts[:custom_message], opts[:custom_message_params] || {}).html_safe
            else
              message = I18n.t(type)
              if status_code == 403
                title = I18n.t("access_denied")
              else
                title = I18n.t("access_denied")
              end
            end
          end
      
          error_page_opts = { title: title, status: status_code, group: opts[:group] }
          error_page_opts = { title: title, status: status_code, group: opts[:group], custom_invalid_access: true }
      
          if show_json_errors
            opts = { type: type, status: status_code }
      
            with_resolved_locale(check_current_user: false) do
              if (request.params[:controller] == "topics" && request.params[:action] == "show") ||
                    (
                      request.params[:controller] == "categories" &&
                        request.params[:action] == "find_by_slug"
                    )
                opts[:extras] = {
                  title: I18n.t("access_denied"),
                  html: build_not_found_page(error_page_opts),
                  group: error_page_opts[:group],
                }
              end
            end
      
            render_json_error message, opts
          else
            begin
              # 404 pages won't have the session and theme_keys without these:
              current_user
              handle_theme
            rescue Discourse::InvalidAccess
              return render plain: message, status: status_code
            end
      
            with_resolved_locale do
              error_page_opts[:layout] = opts[:include_ember] && @_preloaded ? set_layout : "no_ember"
              render html: build_not_found_page(error_page_opts)
            end
          end
        end
      end
    end
    ::ApplicationController.prepend(CustomRescueDiscourseActionsPatch)
  end

  module ::CustomBuildNotFoundPagePatch
  def build_not_found_page(opts = {})

    if opts[:custom_invalid_access]
      # Hide topics and search when custom exception is thrown
      @topics_partial = nil
      @hide_search = true
      @page_title = I18n.t("access_denied")
      @title = opts[:title] || I18n.t("access_denied")
      @current_user =
      begin
        current_user
      rescue StandardError
        nil
      end
      return render_to_string status: opts[:status],
                              layout: opts[:layout],
                              formats: [:html],
                              template: "/exceptions/not_found"
    end
    super(opts)
  end
end
::ApplicationController.prepend(CustomBuildNotFoundPagePatch)

end