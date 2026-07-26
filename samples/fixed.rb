ratio = 0.5
puts "ratio=#{ratio}"
puts "tenth=#{0.1}"
puts "pi=#{3.14}"
puts "sum=#{ratio + 0.25}"
puts "product=#{ratio * 3}"
puts "quotient=#{1.0 / 4}"
puts "scaled=#{(ratio * 100).to_i32}"
puts "neg=#{0.0 - 1.5}"
puts "trunc=#{(0.0 - 1.9).to_i32}"
puts "widen=#{7.to_fixed / 2}"
big = 200.0
puts "saturated=#{big * big}"
if ratio > 0.25
  puts "greater"
end
