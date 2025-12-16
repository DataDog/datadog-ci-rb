# frozen_string_literal: true

# This file references other consumers - testing cross-file dependencies
class CrossReferenceConsumer
  def create_no_deps
    NoDepsConsumer.new
  end

  def create_fully_qualified
    FullyQualifiedConsumer.new
  end

  def use_all
    [
      create_no_deps.compute(1, 2),
      create_fully_qualified.use_base
    ]
  end
end
