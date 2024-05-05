using Distributions, Random, DataFrames, CSV, StatsBase

function standardize(x̄, μ, σ, n::Int64)::Float64
    (x̄ - μ) / (σ / sqrt(n))
end

function sampling_distribution(statistic::Function, d::Distribution, n::Int, r::Int)::Vector{Float64}
    Random.seed!(0)
    sample_statistics = zeros(r)
    sample = zeros(n)

    # Sampling r times and calculating the statistic
    @inbounds for i in 1:r
        rand!(d, sample)
        sample_statistics[i] = statistic(sample)
    end

    sample_statistics
end

function analysis(statistic, d::Distribution, n::Int, r::Int, μ::Real, σ::Real)::Tuple{Float64,Float64,Float64}
    sample_statistics = sampling_distribution(statistic, d, n, r)

    skewness = StatsBase.skewness(sample_statistics)

    z_scores = standardize.(sample_statistics, μ, σ, n)
    upper = sum(z_scores .>= 1.96) / r
    lower = sum(z_scores .<= -1.96) / r

    (upper, lower, skewness)
end

function analyze_distributions(statistic, r::Int64, sample_sizes::Vector{Int64}, distributions)::DataFrame
    println("Analyzing distributions with $(r) repetitions")
    # Some setup
    results = DataFrame(
        "Distribution" => String[],
        "Skewness" => Float64[],
        "Sample Size" => Int64[],
        "Upper Tail" => Float64[],
        "Lower Tail" => Float64[],
        "Sampling Skewness" => Float64[],
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
            upper, lower, sample_skew = analysis(statistic, d, n, r, μ, σ)
            Threads.lock(u) do
                push!(results, (string(d), skewness, n, upper, lower, sample_skew, μ, σ))
            end
        end

    end

    sort!(results, [:Distribution, :"Sample Size"])
end

function main()
    sample_sizes = [1, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 125, 150, 175, 200, 250, 300, 400, 500]
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
    # Compile
    analyze_distributions(mean, 1, sample_sizes, distributions)

    # ~10 minutes on a i7-12700h (10,000,000 repetitions used in the report)
    results::DataFrame = analyze_distributions(mean, 10_000_000, sample_sizes, distributions)

    # ~1 minute on a i7-12700h
    # results::DataFrame = analyze_distributions(mean, 1_000_000, sample_sizes, distributions)

    CSV.write("means.csv", results)
end

function graphing()
    exponential30 = sampling_distribution(mean, Exponential(), 30, 10_000_000)
    gamma30 = sampling_distribution(mean, Gamma(2), 30, 10_000_000)
    lognormal50 = sampling_distribution(mean, LogNormal(0, 0.5), 50, 10_000_000)

    graphing = DataFrame(
        "Exponential 30" => exponential30,
        "Gamma (2, 1) 30" => gamma30,
        "LogNormal (0, 0.5) 50" => lognormal50
    )

    # warning: this will be a large file (~500MB) which is why "graphing.csv" isn't in the repository
    CSV.write("graphing.csv", graphing)
end

main()
graphing()