using LinearAlgebra
using ProgressBars

cosine_distance(x,y) = dot(x,y)/(norm(x)*norm(y))

function best_n(f, data, n)
    res = []
    if isempty(data); return [] end
    for datapoint in data
        value = f(datapoint)
        if isempty(res)
            push!(res, (datapoint, value))
            continue
        end
        if (length(res) == n &&
            value <= res[end][2])
            continue
        end
        j = length(res)
        if length(res) < n
            push!(res, res[end])
        end
        while j > 1 && res[j-1][2] < value
            res[j] = res[j-1]
            j -= 1
        end
        res[j] = (datapoint, value)
    end
    return res
end

function load_data(fname)
    open(fname, "r") do f
        header = readline(f)
        num_words, vec_size = split(header)
        num_words = parse(Int, num_words)
        vec_size = parse(Int, vec_size)

        data = Dict{String, Vector{Float32}}()
        println("Loading word vectors...")
        for _ in ProgressBar(1:num_words)
            word = readuntil(f, ' ')
            word = replace(word, "\n" => "")
            vec = zeros(Float32, vec_size)
            read!(f, vec)
            data[word] = vec
        end
        data
    end
end
