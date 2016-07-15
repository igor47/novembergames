require 'ascii_charts'
require 'googlecharts'
require 'gnuplot'

def roll_and_score(state)
	# roll the unscored dice!
	r = Random.new
	unscored = state.select { |d| !d[:used] }
	unscored.each do |d|
		d[:val] = r.rand(1..6)
	end

	# lets look at just the values of the dice for easinesslesy
	available = unscored.map { |d| d[:val] }

	# check for a straight
	if [1, 2, 3, 4, 5].all? {|d| available.include?(d)} ||
			[2, 3, 4, 5, 6].all? {|d| available.include?(d)}
		return 1500
	end

	# check for a 3 of a kind
	6.downto(1).each do |val|
		just_that_val = available.select {|v| v == val }
		if just_that_val.length >= 3
			# score 3 dice with that value
			3.times do
				d = state.select { |d| !d[:used] && d[:val] == val }.first
				d[:used] = true
			end

			# roll again!
			just_earned = val * 100
			just_earned *= 10 if val == 1
			return just_earned
		end
	end

	# are are down to picking individual dice; how many should we
	# use and how many should we roll again?
	if available.length > 3
		to_use = 1
	else
		to_use = available.length
	end

	score_from_individual_dice = 0
	to_use.times do
		# pick a die with a 1
		d = state.select { |d| !d[:used] && d[:val] == 1 }.first

		# pick one with a 5 if there was no 1
		unless d
			d = state.select { |d| !d[:used] && d[:val] == 5 }.first
		end

		if d
			d[:used] = true
			score_from_individual_dice += d[:val] == 5 ? 50 : 100
		end
	end

	return score_from_individual_dice
end

def decide(opts)
	state, score, strategy = opts.values_at(:state, :score, :strategy)

	# score starts out at 0
	score ||= 0

	# initialize a state if none was passed, or if all dice have been used to score
	if state.nil? || state.all? { |d| d[:used] }
		state = [
			{:val => 0, :used => false,},
			{:val => 0, :used => false,},
			{:val => 0, :used => false,},
			{:val => 0, :used => false,},
			{:val => 0, :used => false,},
		]
	end

	# strategies
	unused_dice = state.select{|d| !d[:used]}
	unused_count = unused_dice.length
	if unused_count == 5
		new_score = roll_and_score(state)
	else
		# if we've reached the target score and have few dice remaining, stop
		if score >= strategy[:target_score] && unused_count <= strategy[:des_dice]
			return score
		end

		# if we have too few dice remaining, stop anyway
		if unused_count <= strategy[:min_dice]
			return score
		end
	
		# haven't decided to stop, lets keep rolling!	
		new_score = roll_and_score(state)
	end

	return 0 if new_score == 0
	return decide({
		:state => state,
		:score => score + new_score,
		:strategy => strategy})
end

def play(times, strategies)
	results = []
	strategies.each do |strategy|
		rounds_to_win = []

		# play a bunch of games with the current strategy
		times.times do
			rounds = 0
			score = 0
			until score >= 4800
				rounds += 1
				score += decide(:strategy => strategy)
			end
			rounds_to_win << rounds
		end

		# calculate distribution of the number of rounds it took to win
		dist = rounds_to_win.inject({}) do |dist, rounds|
			dist[rounds] ||= 0
			dist[rounds] += 1
			dist
		end

		# save the result
		results << {
			:strategy => strategy,
			:rounds_to_win => rounds_to_win,
			:dist => dist,
			:average => average(rounds_to_win),
			:median => median(rounds_to_win),
			:repr => "TS:#{strategy[:target_score]},DD:#{strategy[:des_dice]},MD:#{strategy[:min_dice]}"
		}
	end

	#plot_distribution_of_rounds(results)
	plot_medians_averages(results)
	#puts "In #{times} games, average rounds to win with strategy #{strategy}: #{average(rounds_to_win)}"
end

def plot_medians_averages(results)
	Gnuplot.open do |gp|
		Gnuplot::Plot.new( gp ) do |plot|
			plot.title  "Medians/Averages for Given Strategy"
			plot.xlabel "Strategy"
			plot.ylabel "Median/Average"

			plot.style "fill solid 0.5"

			# draw a histogram
			plot.style "data histogram"
			plot.style "histogram clustered"

			plot.xtics 'nomirror rotate by -45 scale 0 font ",8"' # angled xtics
			#plot.yrange "[0:*]" # don't trim at lowest value

			labels = results.map{ |r| r[:repr] }
			medians = results.map{ |r| r[:median] }
			averages = results.map{ |r| r[:average] }

			plot.data << Gnuplot::DataSet.new( [labels, averages] ) do |ds|
				ds.title = "average"
				ds.using = "2:xticlabels(1)"
			end

			#%[
			plot.data << Gnuplot::DataSet.new( [labels, medians] ) do |ds|
				ds.title = "median"
				ds.using = "2:xticlabels(1)"
			end
			#]
			
			# line at minimal average
			plot.data << Gnuplot::DataSet.new( [averages.min] * averages.length ) do |ds|
				ds.title = "min average (#{averages.min})"
				ds.with = "linespoints"
			end
		end
	end
end

def plot_distribution_of_rounds(results)
	trials = results[0][:rounds_to_win].length
	Gnuplot.open do |gp|
		Gnuplot::Plot.new( gp ) do |plot|
			plot.title  "Number of Games (of #{trials}) won at X rounds of play"
			plot.xlabel "X"
			plot.ylabel "Number of Games"

			results.each do |result|
				dist, strategy = result.values_at(:dist, :strategy)

				keys = dist.keys.sort
				vals = keys.map{|k| dist[k] }

				plot.data << Gnuplot::DataSet.new( [keys, vals] ) do |ds|
					ds.with = "linespoints"
					ds.title = result[:repr]
				end
			end
		end
	end
end

def median(scores)
	scores.sort[scores.length / 2]
end

def average(scores)
	average = scores.inject{ |sum, el| sum + el }.to_f / scores.size
end

def chart(scores)
end

def score_likelihood(scores, score)
	below = 0
	above = 1
	scores.each do |s|
		below += 1 if s < score
		above += 1 if s >= score
	end

	avg = below.to_f / scores.length
	#puts "of #{scores.length} games, #{below} below and #{above} above #{score} (#{avg})"
	return avg
end

def below_chart(scores)
	steps = []
	(0...500).step(50).each{|s| steps << [s, 1 - score_likelihood(scores, s)]}
	(500...1000).step(100).each{|s| steps << [s, 1 - score_likelihood(scores, s)]}
	(1000...scores.max).step(250).each{|s| steps << [s, 1 - score_likelihood(scores, s)]}
	#puts AsciiCharts::Cartesian.new(steps).draw
	Gnuplot.open do |gp|
		Gnuplot::Plot.new( gp ) do |plot|
			plot.title  "Probability of Score > X"
			plot.xlabel "X"
			plot.ylabel "Probability"

			keys = steps.map{|s| s[0] }
			vals = steps.map{|s| s[1] }

			plot.data << Gnuplot::DataSet.new( [keys, vals] ) do |ds|
				ds.with = "linespoints"
				ds.notitle
			end
		end
	end
end

strategies = [
	{:target_score => 500, :min_dice => 3, :des_dice => 3},
	{:target_score => 500, :min_dice => 2, :des_dice => 2},
	{:target_score => 700, :min_dice => 2, :des_dice => 3},
	{:target_score => 900, :min_dice => 2, :des_dice => 3},
	{:target_score => 500, :min_dice => 2, :des_dice => 3},

	# {:target_score => 400, :min_dice => 3, :des_dice => 3},
	# {:target_score => 500, :min_dice => 3, :des_dice => 3},
	# {:target_score => 600, :min_dice => 3, :des_dice => 3},
	# {:target_score => 700, :min_dice => 3, :des_dice => 3},
	# {:target_score => 800, :min_dice => 3, :des_dice => 3},
	# {:target_score => 900, :min_dice => 3, :des_dice => 3},

	# explore these next
	# {:target_score => 300, :min_dice => 2, :des_dice => 2},
	# {:target_score => 500, :min_dice => 2, :des_dice => 2},
	# {:target_score => 700, :min_dice => 2, :des_dice => 2},
	# {:target_score => 900, :min_dice => 2, :des_dice => 2},

	# if you have only one die left, stop rolling
	# {:target_score => 300, :min_dice => 1, :des_dice => 3},
	# {:target_score => 500, :min_dice => 1, :des_dice => 3},
	# {:target_score => 700, :min_dice => 1, :des_dice => 3},
	# {:target_score => 900, :min_dice => 1, :des_dice => 3},
	
	# what if you always go for broke? nope, turns out, bad idea
	# {:target_score => 300, :min_dice => 0, :des_dice => 3},
	# {:target_score => 500, :min_dice => 0, :des_dice => 3},
	# {:target_score => 700, :min_dice => 0, :des_dice => 3},
	# {:target_score => 900, :min_dice => 0, :des_dice => 3},

	# if you have only one die left, stop rolling
	#{:target_score => 300, :min_dice => 1, :des_dice => 2},
	#{:target_score => 500, :min_dice => 1, :des_dice => 2},
	#{:target_score => 700, :min_dice => 1, :des_dice => 2},
	#{:target_score => 900, :min_dice => 1, :des_dice => 2},

	# does not work in your favor; also makes no sense.
	# why would you  keep rolling if you're over target, but stop if under?
	# {:target_score => 300, :min_dice => 2, :des_dice => 1},
	# {:target_score => 500, :min_dice => 2, :des_dice => 1},
	# {:target_score => 700, :min_dice => 2, :des_dice => 1},
	# {:target_score => 900, :min_dice => 2, :des_dice => 1},

	# these are waaay too aggressive, you're gonna loose
	#{:target_score => 300, :min_dice => 1, :des_dice => 1},
	#{:target_score => 500, :min_dice => 1, :des_dice => 1},
	#{:target_score => 700, :min_dice => 1, :des_dice => 1},
	#{:target_score => 900, :min_dice => 1, :des_dice => 1},

]
play(10_000, strategies)

#score_likelihood(scores, 1500)
#below_chart(scores)
