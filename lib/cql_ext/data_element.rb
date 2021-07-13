module QDM
  # Represents QDM datatype (parent class of all generated QDM datatype models)
  class DataElement
    embeds_many :dataElementAttributes
    field :encounter_id, type: BSON::ObjectId
    field :denormalize_as_datetime, type: Boolean
  end

  class DataElementAttribute
    include Mongoid::Document
    field :attribute_valueset, type: String
    field :attribute_name, type: String
  end
end
