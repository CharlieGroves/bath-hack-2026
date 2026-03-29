# Finds or creates an EstateAgent from a Property’s +agent_name+ using the Google Places
# gateway, caching by normalized +lookup_key+ and +google_place_id+.
class EstateAgentResolver
  def initialize(property, gateway: Gateways::LettingAgentQualityGateway.new)
    @property = property
    @gateway  = gateway
  end

  # Links @property to an EstateAgent row; returns the EstateAgent or nil.
  def call
    name = @property.agent_name
    return nil if name.blank?

    key = self.class.normalize_lookup_key(name)

    existing = EstateAgent.find_by(lookup_key: key)
    if existing
      attach_property(existing)
      return existing
    end

    data = @gateway.fetch_letting_agent_data(name)
    return nil unless data && data[:place_id].present?

    agent = EstateAgent.find_or_initialize_by(google_place_id: data[:place_id])
    agent.lookup_key    = key if agent.new_record? || agent.lookup_key.blank?
    agent.display_name  = data[:name]
    agent.rating        = data[:rating] if data[:rating].present?
    agent.save!

    attach_property(agent)
    agent
  rescue Gateways::LettingAgentQualityGateway::Error => e
    Rails.logger.warn("[EstateAgentResolver] #{e.message}")
    nil
  end

  def self.normalize_lookup_key(name)
    name.to_s.downcase.gsub(/\s+/, " ").strip
  end

  private

  def attach_property(agent)
    return if @property.estate_agent_id == agent.id

    @property.update_column(:estate_agent_id, agent.id)
  end
end
