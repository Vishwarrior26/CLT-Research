using Distributions, Random, DataFrames, CSV, StatsBase

function t_statistic(data::Vector, μ::Float64)
    (mean(data) - μ) / (std(data) / sqrt(length(data)))
end

function analysis(statistic::Function, d::Distribution, n::Int64, r::Int64, μ::Number, σ::Number)
    Random.seed!(0)
    sample_statistics = zeros(r)
    sample = zeros(n)

    @inbounds for i in 1:r
        rand!(d, sample)
        if statistic == mean
            sample_statistics[i] = statistic(sample)
        elseif statistic == t_statistic
            sample_statistics[i] = statistic(sample, μ)
        end
    end

    m = mean(sample_statistics)
    s = std(sample_statistics)
    skewness = StatsBase.skewness(sample_statistics)
    kurtosis = StatsBase.kurtosis(sample_statistics) # excess kurtosis

    μ::Float64 = mean(d)
    σ::Float64 = std(d)

    z_scores = (sample_statistics .- μ) ./ (σ / sqrt(n))
    upper = sum(z_scores .>= 1.96) / r
    lower = sum(z_scores .<= -1.96) / r

    (upper, lower, m, s, skewness, kurtosis)
end

function analyze_distributions(statistic::Function, critical::Float64, r::Number)::DataFrame
    println("Analyzing distributions with $(r) repetitions")

    sample_sizes = [1, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 125, 150, 175, 200, 250, 300, 400, 500]
    distributions = [
        Gamma(16),
        LogNormal(0, 0.25),
        Gamma(4),
        Gamma(2),
        LogNormal(0, 0.5),
        Gamma(1),
        Exponential(),
        LogNormal(0, 0.75)
    ]

    results = DataFrame(
        Distribution=String[],
        Skewness=Float64[],
        Sample_Size=Int[],
        Upper_Tail=Float64[],
        Lower_Tail=Float64[],
        Tail_Sum=Float64[],
        Tail_Difference=Float64[],
        Sampling_Mean=Float64[],
        Sampling_SD=Float64[],
        Sampling_Skewness=Float64[],
        Sampling_Kurtosis=Float64[],
        Population_Mean=Float64[],
        Population_SD=Float64[]
    )

    @inbounds for d::Distribution in distributions
        println("$(string(d))")

        μ::Float64 = mean(d)
        σ::Float64 = std(d)
        skewness::Float64 = StatsBase.skewness(d)

        u = Threads.SpinLock()
        @inbounds Threads.@threads for n in sample_sizes
            upper, lower, m, s, sample_skew, sample_kurt = analysis(statistic, d, n, r, μ, σ)
            Threads.lock(u) do
                push!(results, (string(d), skewness, n, upper, lower, upper + lower, upper - lower, m, s, sample_skew, sample_kurt, μ, σ))
            end
        end

    end

    sort!(results, [:Distribution, :Sample_Size])
end


using Plots, StatsPlots
sample_statistics = analysis(mean, Normal(), 5, 100000, quantile(Normal(), 0.975), 0, 1)
m = mean(sample_statistics)
s = std(sample_statistics)
skewness = StatsBase.skewness(sample_statistics)
kurtosis = StatsBase.kurtosis(sample_statistics)

upper = sum(sample_statistics .>= m + quantile(Normal(), 0.975) * s) / 100000
lower = sum(sample_statistics .<= m - quantile(Normal(), 0.975) * s) / 100000
# histogram of sample_statistics
histogram(sample_statistics, bins=100)

qqplot(Normal(), sample_statistics)

CSV.write("qq.csv", DataFrame(sample_statistics=sample_statistics))

# compile
analyze_distributions(mean, quantile(Normal(), 0.975), 1)
analyze_distributions(t_statistic, quantile(Normal(), 0.975), 1)

@time CSV.write("test.csv", analyze_distributions(mean, quantile(Normal(), 0.975), 1000000))

@time results = analyze_distributions(mean, quantile(Normal(), 0.975), 100000)
CSV.write("CLT_means.csv", results)

# @time results = analyze_distributions(t_statistic, quantile(TDist(100000 - 1), 0.975), 100000)
# CSV.write("CLT_t.csv", results)

# @code_warntype analyze_distributions(mean, quantile(Normal(), 0.975), 1000)

# using BenchmarkTools
# @profview analyze_distributions(mean, quantile(Normal(), 0.975), 10000)
# @btime analyze_distributions(mean, quantile(Normal(), 0.975), 1000)