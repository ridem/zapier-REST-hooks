module ZapierRestHooks
  class Hook < ActiveRecord::Base
    validates :event_name, :owner_id, :owner_class_name, :subscription_url, :target_url,
              presence: true

    # Looks for an appropriate REST hook that matches the owner, and triggers the hook if one exists.
    def self.trigger(event_name, record, owner)
      hooks = self.hooks(event_name, owner)
      return if hooks.empty?

      unless Rails.env.development?
        # Trigger each hook if there is more than one for an owner, which can happen.
        hooks.each do |hook|
          # These use puts instead of Rails.logger.info because this happens from a Resque worker.
          Rails.logger.info "Triggering REST hook: #{hook.inspect}"
          Rails.logger.info "REST hook event: #{event_name}"
          encoded_record = record.to_json
          Rails.logger.info "REST hook record: #{encoded_record}"
          RestClient.post(hook.target_url, encoded_record) do |response, request, result|
            if response.code.eql? 410
              Rails.logger.info "Destroying REST hook because of 410 response: #{hook.inspect}"
              hook.destroy
            end
          end
        end
      end
    end

    # Returns all hooks for a given event and owner.
    def self.hooks(event_name, owner)
      where(event_name: event_name, owner_class_name: owner.class.name, owner_id: owner.id)
    end

    # Tests whether any hooks exist for a given event and account, for deciding whether or not to
    # enqueue Resque jobs.
    def self.hooks_exist?(event_name, owner)
      self.hooks(event_name, owner).size > 0
    end

  end
end