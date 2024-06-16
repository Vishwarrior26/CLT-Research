using Distributions, Random, DataFrames, CSV, StatsBase

"""
    standardize(x, μ, σ, n=1)

Standardize a value `x` given the mean `μ`, standard deviation `σ`, and sample size `n` of some data x belongs to.
"""
function standardize(x, μ, σ, n::Int64=1)::Float64
    (x - μ) / (σ / sqrt(n))
end

"""
    standardize(data)

Standardize a vector by converting to z-scores.
"""
function standardize(data::Vector{Float64})::Vector{Float64}
    standardize.(data, mean(data), std(data))
end

"""
    t_score(x, μ, σ, n)

Standardize a vector by converting to t-scores.
"""
function t_score(data::Vector{Float64}; μ::Real)::Vector{Float64}
    standardize.(data, μ, std(data), length(data))
end

"""
    sampling_distribution(statistic, d, n, r; args...)

Generate a sampling distribution of a statistic `statistic` given a distribution `d`, sample size `n`, and number of repetitions `r`. Optional arguments passed to statistic function.
"""
function sampling_distribution(statistic::Function, d::Distribution, n::Int, r::Int; args...)::Vector{Float64}
    Random.seed!(0)
    # Preallocating vectors for speed
    sample_statistics = zeros(r)
    sample = zeros(n)

    # Sampling r times and calculating the statistic
    @inbounds for i in 1:r
        rand!(d, sample) # in-place to reduce memory allocation
        sample_statistics[i] = statistic(sample; args...)::Float64
    end

    sample_statistics
end

function analysis(statistic::Function, d::Distribution, n::Int, r::Int, μ::Real, σ::Real, critical::Float64; args...)::Tuple{Float64,Float64,Float64,Float64}
    statistics = sampling_distribution(statistic, d, n, r; args...)
    skewness = StatsBase.skewness(statistics)
    kurtosis = StatsBase.kurtosis(statistics)

    # Standardizing the values to look at tail probabilities
    z_scores = zeros(r)
    zscore!(z_scores, statistics, μ, σ / sqrt(n))

    # Calculating tail probabilities
    upper = sum(z_scores .>= critical) / r
    lower = sum(z_scores .<= -critical) / r

    (upper, lower, skewness, kurtosis)
end

function analyze_distributions(statistic::Function, r::Int, sample_sizes::Vector{Int}, critical::Function, distributions, params=false)::DataFrame
    println("Analyzing sampling distributions of $(statistic)s with $(r) repetitions")
    # Setting up the results we're interested in
    results = DataFrame(
        "Distribution" => String[],
        "Skewness" => Float64[],
        "Sample Size" => Int64[],
        "Upper Tail" => Float64[],
        "Lower Tail" => Float64[],
        "Sampling Skewness" => Float64[],
        "Sampling Kurtosis" => Float64[],
        "Population Mean" => Float64[],
        "Population SD" => Float64[]
    )

    # Analyzing each distribution
    @inbounds for d::Distribution in distributions
        println(string(d))

        # Getting population parameters
        μ = mean(d)
        σ = std(d)
        skewness = StatsBase.skewness(d)

        # Analyzing each sample size
        u = Threads.SpinLock() # lock to avoid data races
        @inbounds Threads.@threads for n in sample_sizes
            if params
                upper, lower, sample_skewness, sample_kurtosis = analysis(statistic, d, n, r, μ, σ, abs(critical(n)), μ=μ)
            else
                upper, lower, sample_skewness, sample_kurtosis = analysis(statistic, d, n, r, μ, σ, abs(critical(n)))
            end
            Threads.lock(u) do
                push!(results, (string(d), skewness, n, upper, lower, sample_skewness, sample_kurtosis, μ, σ))
            end
        end

    end

    sort!(results, [:Distribution, :"Sample Size"])
end

function main(r)
    sample_sizes = [5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 125, 150, 175, 200, 250, 300, 350, 400, 450, 500]
    distributions = [
        Gamma(16),
        LogNormal(0, 0.25),
        Gamma(4),
        Gamma(2),
        LogNormal(0, 0.5),
        Gamma(1),
        Exponential(),
        Gamma(0.64),
        LogNormal(0, 0.75)
    ]
    # tstar = n -> quantile(TDist(n), 0.975)
    zstar = n -> quantile(Normal(), 0.975)

    # Compile
    analyze_distributions(mean, 1, sample_sizes, zstar, distributions)
    # analyze_distributions(t_score, 1, sample_sizes, tstar, distributions, true)

    # Warning: this code will take a very long time to run if used with a large r. We used r = 1_000_000
    @time means::DataFrame = analyze_distributions(mean, r, sample_sizes, zstar, distributions)
    CSV.write("means.csv", means)

    # @time t::DataFrame = analyze_distributions(t_score, r, sample_sizes, tstar, distributions, true)
    # CSV.write("t.csv", t)

    nothing
end

function graphing(r)
    d = Exponential()
    n = 30
    μ = mean(d)
    σ = std(d)
    # Creating sampling distributions
    exponential30 = sampling_distribution(mean, d, n, r)
    exponential30std = zeros(r)
    zscore!(exponential30std, exponential30, μ, σ / sqrt(n))
    # exponential30std = standardize(exponential30)

    n = 150
    exponential150 = sampling_distribution(mean, d, n, r)
    exponential150std = zeros(r)
    zscore!(exponential150std, exponential150, μ, σ / sqrt(n))
    # exponential150std = standardize(exponential150)

    graphing = DataFrame(
        "Exponential 30" => exponential30,
        "Exponential 30 Z-Scores" => exponential30std,
        "Exponential 150" => exponential150,
        "Exponential 150 Z-Scores" => exponential150std
    )

    CSV.write("graphing.csv", graphing)

    nothing
end

# main(1_000_000)
# graphing(1_000_000)

function adjustedSkew(x)
    n = length(x)
    sqrt(n * (n - 1)) / (n - 2) * skewness(x)
end

function RAS(x; d)
    # sample skewness/population skewness
    adjustedSkew(x) / skewness(d)
end

function testing(r=1_000_000)
    distributions = [
        Gamma(16),
        LogNormal(0, 0.25),
        Gamma(4),
        Gamma(2),
        LogNormal(0, 0.5),
        Gamma(1),
        Exponential(),
        Gamma(0.64),
        LogNormal(0, 0.75)
    ]
    results = DataFrame(
        "Distribution" => String[],
        "SampleSize" => Int64[],
        "PopulationSkewness" => Float64[],
        "Median" => Float64[],
        "IQR" => Float64[],
        "Sampling Distro Skewness" => Float64[],
    )
    for d in distributions
        println(string(d))
        n = round(Int, (skewness(d))^2 * 36)
        f(x) = 1.25 * adjustedSkew(x)
        x = sampling_distribution(f, d, n, r)
        push!(results, (string(d), n, skewness(d), median(x), quantile(x, 0.75) - quantile(x, 0.25), skewness(x)))
    end

    results
end

df = testing()
println(df)

#regression log(median) against sample size in df
# ols = lm(@formula(Median^2 ~ PopulationSkewness), df)
# ols
# r2(ols)

# Regression median col of df against sample size
# using GLM
# ols = lm(@formula(Median ~ PopulationSkewness), df)
# ols
# r2(ols)
# scatterplot of median against sample size
# using Plots
# scatter(df.SampleSize, df.Median, group=df.Distribution, xlabel="Sample Size", ylabel="Median", title="Median vs Sample Size", legend=:bottomright)
# n = 30
# z = sampling_distribution(RAS, d, n, 1_000_000; d=d)
# histogram(z, bins=100, label="RAS of Exponential", xlabel="RAS", ylabel="Frequency", title="Histogram of RAS of Exponential", legend=:topleft)
# println(n)
# println("median: ", median(z))
# println("IQR: ", quantile(z, 0.75) - quantile(z, 0.25))
# println("skewness: ", skewness(z))

# using Plots
# # d = Gamma(0.64)
# d = Exponential()
# n = round(Int, skewness(d)^2 * 36)
# n = 30

# x = sampling_distribution(RAS, d, n, 1_000_000; d)
# histogram with median and iqr labels
# histogram(x, bins=100, xlabel="Skewness", ylabel="Frequency", title="Sample Skewness/Pop Skewness")

# println("median: ", median(x))
# println("IQR: ", quantile(x, 0.75) - quantile(x, 0.25))
# println("skewness: ", skewness(x))
# println()

# y = sampling_distribution(skewness, d, n, 1_000_000)
# histogram(y, bins=100, label="Skewness of Exponential", xlabel="Skewness", ylabel="Frequency", title="Histogram of Skewness of Exponential", legend=:topleft)
# println("median: ", median(y))
# println("IQR: ", quantile(y, 0.75) - quantile(y, 0.25))
# println("skewness: ", skewness(y))
# println()

# println(mean(x - y))

# analysis(mean, Exponential(), 75, 1_000_000, mean(Exponential()), std(Exponential()), 1.96)

