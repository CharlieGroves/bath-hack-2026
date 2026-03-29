class ModelSearch < ApplicationRecord
  STATUSES = %w[pending complete failed].freeze

  validates :prompt, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :pending,  -> { where(status: "pending") }
  scope :complete, -> { where(status: "complete") }

  def pending?  = status == "pending"
  def complete? = status == "complete"
  def failed?   = status == "failed"

  def mark_complete!(ids, filters)
    update!(status: "complete", result_ids: ids, filters: filters)
  end

  def mark_failed!(message)
    update!(status: "failed", error_message: message)
  end
end
