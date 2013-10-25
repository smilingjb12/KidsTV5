require 'set'

class LFSR
  attr_accessor :polynom_indexes
  
  def initialize(polynom_indexes) # [0, 0, 1, 1] => 1 + x**3 + x**4
	  @polynom_indexes = polynom_indexes
	  @triggers = [1] + [0] * (polynom_indexes.size - 1)
  end
  
  def run_once
    prev_state = @triggers
    @triggers = @triggers.rotate(-1)
	  @triggers[0] = prev_state
	    .zip(@polynom_indexes)
	    .map { |a, b| a & b }
	    .reduce(:^)
    triggers
  end
  
  def run
    first_state = @triggers.dup
    states = [first_state]
    loop do
      run_once
      states << @triggers.dup
      break if @triggers == first_state
    end
    states.pop # last state == first state
    states
  end

  def triggers
    @triggers.dup
  end
end

class Scheme
  def run(test, faulty_node = nil, fault = nil)
    fail "test must have 7 inputs" if test.size != 7
    xs = test.dup
    fs = [0] * 6
    f_index = nil
    if fault
      f_index = faulty_node[1].to_i - 1
      if faulty_node.start_with? 'x'
        xs[f_index] = fault
      elsif faulty_node.start_with? 'f'
        fs[f_index] = fault
      end
    end
    fs[0] = nand2(xs[0], xs[1]) unless fault && f_index == 0
    fs[1] = nand1(xs[2]) unless fault && f_index == 1
    fs[2] = and2(xs[4], xs[5]) unless fault && f_index == 2
    fs[3] = and3(xs[3], fs[2], xs[6]) unless fault && f_index == 3
    fs[4] = xor2(fs[1], fs[3]) unless fault && f_index == 4
    fs[5] = nand2(fs[0], fs[4]) unless fault && f_index == 5
  end

  private
  
  def xor2(a, b)
    a ^ b
  end

  def nand2(a, b)
    (a & b) == 0 ? 1 : 0
  end
  
  def nand1(a)
    a == 0 ? 1 : 0
  end

  def and2(a, b)
    a & b
  end
  
  def and3(a, b, c)
    a & b & c
  end
end

class CoverageTable
  def initialize(sets)
    @sets = sets
  end
  
  def nodes
    @nodes ||= @sets.values
      .flatten
      .map { |hash| hash.values }
      .flatten
      .uniq
  end
  
  def covered_nodes_for(params)
    test = params[:test]
    fault = params[:fault]
    @sets[test].select { |hash| hash.key? fault }
      .map { |hash| hash.values }
      .flatten
      .uniq
  end
end

class CoverageTableBuilder
  def initialize(params)
    @scheme = params[:scheme]
  end

  def build
    sets = Hash.new { |hash, key| hash[key] = [] }
		nodes = [*1..7].map { |i| "x#{i}" } + [*1..6].map { |i| "f#{i}" }
		nodes.each do |node|
		  [0, 1].each do |fault|
		    [0, 1].repeated_permutation(7).each do |xs|
		      test = @scheme.run(xs, node, fault)
		      correct = @scheme.run(xs)
		      sets[xs] << { fault => node } if test != correct
		    end
		  end
		end
		sets
  end
end

class SignatureAnalyzer
  def initialize(params)
		@polynom_indexes = params[:polynom_indexes]
  	@triggers = [0] * @polynom_indexes.size
  end

  def run(input)
  	fail "Input must be an array" unless input.is_a? Array
    [@triggers.dup] + input.map { |x| run_once(x) }
  end

  def run_once(x)
  	fail "Input must be 0 or 1" unless (0..1).include? x
    @triggers.rotate!
    @triggers[-1] = @triggers
      .zip(@polynom_indexes)
      .map { |a, b| a & b }
      .reduce(:^) ^ x
    triggers
  end

  def reset
    @triggers.map! { 0 }
  end

  def triggers
    @triggers.dup
  end
end

scheme = Scheme.new
builder = CoverageTableBuilder.new(scheme: scheme)
table = CoverageTable.new(builder.build)

DEBUG_STEPS = false
TABLE_HEADER = "Coverage Adders Polynom"
puts TABLE_HEADER
puts '-' * 80
[0, 1].repeated_permutation(9).drop(1).each do |sa_polynom|
  lfsr = LFSR.new [1, 1, 1, 0, 1, 1, 1] # x1 + x2 + x3 + x5 + x6 + x7
  sa = SignatureAnalyzer.new(polynom_indexes: sa_polynom)
  all_sa_polynoms = []
  lfsr.run.each do
    puts "lfsr: #{lfsr.triggers}" if DEBUG_STEPS
    all_sa_polynoms << sa.triggers unless all_sa_polynoms.include?(sa.triggers)
    lfsr_triggers = lfsr.run_once
    scheme_output = scheme.run(lfsr_triggers)
    sa_triggers = sa.run_once(scheme_output)
    puts "out:  #{scheme_output}" if DEBUG_STEPS
    puts "sa:   #{sa_triggers}" if DEBUG_STEPS
    puts if DEBUG_STEPS
    gets if DEBUG_STEPS
  end
  coverage = all_sa_polynoms.size * 100.0 / (2**7 - 1)
  coverage = format("%.2f%", coverage)
  adders_count = sa_polynom.reduce(:+)
  sa_polynom_string = sa_polynom
    .map.with_index { |x, i| [x, sa_polynom.size - i] }
    .select { |x, i| x > 0 }
    .map { |x, i| "x#{i}" }
    .join(' + ') + ' + 1'
  puts "#{coverage}   #{adders_count}      #{sa_polynom_string}"
end
puts '-' * 80
puts TABLE_HEADER