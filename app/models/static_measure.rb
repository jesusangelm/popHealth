class StaticMeasure
  include Mongoid::Document

  field :measure_id, type: String
  field :cms_id, type: String
  field :initial_population, type: String
  field :denominator, type: String
  field :denominator_exclusions, type: String
  field :numerator, type: String
  field :numerator_exclusions, type: String
  field :denominator_exceptions, type: String
  field :stratification, type: String
  field :terminology, type: Array
  field :data_criteria, type: Array
end