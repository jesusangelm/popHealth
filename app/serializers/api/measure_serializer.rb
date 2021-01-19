class Api::MeasureSerializer < ActiveModel::Serializer
  attributes :_id, :title, :category, :hqmf_id, :reporting_program_type, :cms_id
end
