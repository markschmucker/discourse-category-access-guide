# frozen_string_literal: true

# name: discourse-category-access-guide
# about: A Discourse plugin that displays category-specific access messages, guiding users on how to gain entry based on predefined access rules.
# version: 0.1
# authors: Jahan Gagan
# url: https://github.com/jahan-ggn/discourse-category-access-guide

enabled_site_setting :discourse_category_access_guide_enabled

after_initialize do
  module ::DiscourseCategoryAccessGuide
    class CustomInvalidAccess < StandardError
      attr_reader :custom_message, :custom_message_params

      def initialize(msg = nil, opts = {})
        super(msg)

        opts ||= {}

        @custom_message = opts[:custom_message]
        @custom_message_params = opts[:custom_message_params]
      end
    end
  end

  module ::TopicsControllerCAGExtension
    def self.prepended(base)
      base.rescue_from ::DiscourseCategoryAccessGuide::CustomInvalidAccess do |e|
        handle_custom_invalid_access(e)
      end
    end

    def show
      super
    rescue Discourse::InvalidAccess => e
      handle_invalid_access(e)
    end

    private

    def handle_invalid_access(_e)
      topic_id = params[:topic_id].to_i
      raise Discourse::InvalidAccess if topic_id.blank?

      topic = Topic.find_by(id: topic_id)
      raise Discourse::InvalidAccess if topic.nil?

      category_id = topic.category_id
      category_access_map = JSON.parse(SiteSetting.category_access_map || "{}")

      if category_id.present? && category_access_map.key?(category_id.to_s)
        topic_guide_url = category_access_map[category_id.to_s]
        if SiteSetting.discourse_category_access_guide_enabled
          raise ::DiscourseCategoryAccessGuide::CustomInvalidAccess.new(
                  "error_message",
                  custom_message: "error_message",
                  custom_message_params: {
                    url: topic_guide_url,
                  },
                )
        end
      end

      raise Discourse::InvalidAccess
    end

    def handle_custom_invalid_access(e)
      opts = { custom_message: e.custom_message, custom_message_params: e.custom_message_params }
      render_custom_not_found_page(403, opts)
    end

    def render_custom_not_found_page(status_code, opts = {})
      opts ||= {}

      show_json_errors = request.format.json? || request.xhr? || params[:format] == "json"

      title = I18n.t("access_denied")

      if show_json_errors
        render_json_error(message, type: :custom_invalid_access, status: status_code)
      else
        @topics_partial = nil
        @hide_search = true
        @page_title = title
        @title = I18n.t(opts[:custom_message], opts[:custom_message_params] || {}).html_safe
        @current_user =
          begin
            current_user
          rescue StandardError
            nil
          end

        render status: status_code,
               layout: "no_ember",
               formats: [:html],
               template: "/exceptions/not_found"
      end
    end
  end

  ::TopicsController.prepend(TopicsControllerCAGExtension)
end
