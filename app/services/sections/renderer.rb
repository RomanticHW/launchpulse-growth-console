module Sections
  class Renderer
    PARTIALS = Section::KINDS.index_with { |kind| "sections/#{kind}" }.freeze

    def initialize(section)
      @section = section
    end

    def partial_path
      PARTIALS.fetch(@section.kind, "sections/unknown")
    end
  end
end
