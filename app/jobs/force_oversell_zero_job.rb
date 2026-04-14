# frozen_string_literal: true

class ForceOversellZeroJob < ApplicationJob
  queue_as :sync_stock

  retry_on StandardError,
           wait: ->(executions) { [ executions * 10, 120 ].min.seconds },
           attempts: 10

  discard_on ActiveRecord::RecordNotFound

  def perform(oversell_incident_id)
    incident = OversellIncident.find(oversell_incident_id)
    return :skipped unless incident.status == "open"

    StockSync::ForceZeroOnOversell.call!(oversell_incident: incident)
  end
end
