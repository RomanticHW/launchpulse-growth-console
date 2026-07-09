module ApplicationHelper
  def display_diff_value(value)
    case value
    when Hash, Array
      JSON.pretty_generate(value)
    when nil
      "未设置"
    else
      value.to_s
    end
  end

  def sparkline_path(values, width: 72, height: 18, padding: 2)
    points = sparkline_points(values, width:, height:, padding:)
    return "" if points.empty?

    first_x, first_y = points.first
    path = "M #{svg_number(first_x)},#{svg_number(first_y)}"
    points.each_cons(2) do |from, to|
      from_x, from_y = from
      to_x, to_y = to
      midpoint_x = (from_x + to_x) / 2.0
      path << " C #{svg_number(midpoint_x)},#{svg_number(from_y)} #{svg_number(midpoint_x)},#{svg_number(to_y)} #{svg_number(to_x)},#{svg_number(to_y)}"
    end
    path
  end

  def sparkline_area_path(values, width: 72, height: 18, padding: 2)
    points = sparkline_points(values, width:, height:, padding:)
    return "" if points.empty?

    "#{sparkline_path(values, width:, height:, padding:)} L #{svg_number(points.last.first)},#{height} L #{svg_number(points.first.first)},#{height} Z"
  end

  private

  def sparkline_points(values, width:, height:, padding:)
    numbers = Array(values).map(&:to_f)
    return [] if numbers.empty?

    numbers = numbers * 2 if numbers.one?
    min, max = numbers.minmax
    range = max - min
    step = width.to_f / (numbers.size - 1)
    usable_height = height - (padding * 2)

    numbers.each_with_index.map do |value, index|
      x = step * index
      y = if range.zero?
        height / 2.0
      else
        padding + ((max - value) / range * usable_height)
      end
      [ x, y ]
    end
  end

  def svg_number(number)
    format("%.2f", number).sub(/\.?0+\z/, "")
  end
end
