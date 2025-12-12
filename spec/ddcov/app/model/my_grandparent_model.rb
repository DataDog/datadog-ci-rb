require_relative "../../vendor/base_model"
require_relative "../concerns/queryable"

class MyGrandparentModel < BaseModel
  include Queryable
end
