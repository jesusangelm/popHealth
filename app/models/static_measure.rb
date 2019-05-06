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
  field :stratification, type: Array
  field :terminology, type: Array
  field :data_criteria, type: Array
  field :measure_population, type: String
  field :measure_population_exclusions, type: String
  field :measure_observation, type: String
  field :population_criteria, type: Array
  field :definition, type: String
end
