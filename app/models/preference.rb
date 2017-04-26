class Preference
  include Mongoid::Document

  field :selected_measure_ids, type: Array, default: []
  field :mask_phi_data, type: Boolean, default: false
  field :should_display_circle_visual, type: Boolean, default: true
  field :population_chart_scaled_to_IPP, type: Boolean, default: false
  field :should_display_provider_tree, type: Boolean, default: false
  field :show_aggregate_result, type: Boolean, default: false
  field :c4filters, type: Array, default: []
  belongs_to :user
end
