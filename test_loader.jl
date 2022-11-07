include("word2vec_loader.jl")

#data = load_data("../data/text8-vector.bin")
data = load_data("../../GoogleNews-vectors-negative300.bin")
hello_vec = data["hello"]

closest = best_n(((_,vec),) -> cosine_distance(vec, hello_vec), data, 20)
for ((word, vec), dist) in closest
    println(word, "     ", dist)
end
