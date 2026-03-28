class EstateAgentLinkJob < ApplicationJob
  queue_as :default

  def perform(property_id)
    property = Property.find_by(id: property_id)
    return unless property&.agent_name.present?

    EstateAgentResolver.new(property).call
  end
end
