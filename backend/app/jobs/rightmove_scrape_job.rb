class RightmoveScrapeJob < ApplicationJob
  queue_as :scraping

  # Scrapes a single Rightmove listing and upserts the Property record.
  # Enqueues PropertyEnrichmentJob if the property is new or enrichment is stale.
  #
  # Args:
  #   rightmove_id  - e.g. "172607297"
  #   scrape_run_id - optional ScrapeRun id for audit logging
  def perform(rightmove_id, scrape_run_id: nil)
    Rails.logger.info("[RightmoveScrapeJob] START #{rightmove_id}")

    scraper = RightmoveScraper.new
    attrs   = scraper.fetch_listing(rightmove_id)

    property  = Property.find_or_initialize_by(rightmove_id: rightmove_id)
    is_new    = property.new_record?
    property.assign_attributes(attrs)
    property.save!

    action = is_new ? "created" : "updated"
    Rails.logger.info("[RightmoveScrapeJob] #{action.upcase} #{rightmove_id} — #{property.address_line_1}, #{property.postcode}")

    update_scrape_run(scrape_run_id, is_new)

  rescue RightmoveScraper::ScrapingError => e
    Rails.logger.error("[RightmoveScrapeJob] ERROR #{rightmove_id}: #{e.message}")
    mark_scrape_run_error(scrape_run_id, e.message)
    raise # re-raise so Sidekiq retries
  end

  private

  def update_scrape_run(scrape_run_id, is_new)
    return unless scrape_run_id
    run = ScrapeRun.find_by(id: scrape_run_id)
    return unless run

    run.with_lock do
      run.properties_found   = (run.properties_found   || 0) + 1
      run.properties_new     = (run.properties_new     || 0) + (is_new ? 1 : 0)
      run.properties_updated = (run.properties_updated || 0) + (is_new ? 0 : 1)
      run.save!
    end
  end

  def mark_scrape_run_error(scrape_run_id, message)
    return unless scrape_run_id
    ScrapeRun.find_by(id: scrape_run_id)&.update(status: "failed", error_message: message)
  end
end
