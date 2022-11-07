function load_word_table(fname)
    words = String[]
    for line in eachline(fname)
        append!(words, split(line))
    end
    return words
end

function load_secret_table(fname)
    labels = Symbol[]
    d = Dict(
        "B" => :blue,
        "R" => :red,
        "." => :empty,
        "#" => :assassin,
    )
    for line in eachline(fname)
        for str_label in split(line)
            push!(labels, d[str_label])
        end
    end
    return labels
end

mutable struct HintMemory
    num :: Int
    word :: String
    candidates :: Vector{Tuple{String, Float32, Symbol}}
    team :: Symbol
end

struct CodeNamesGuesser
    word_database :: Dict{String, Vector{Float32}}
    active_words :: Vector{Tuple{String, Vector{Float32}}}
    team :: Symbol
    active_hints :: Vector{HintMemory}
end

function CodeNamesGuesser(word_database::Dict{String, Vector{Float32}}, words::Vector{String}, team::Symbol)
    @assert team in (:red, :blue)
    @assert length(Set(words)) == length(words) # no duplicities
    word_vecs = [
        (word, word_database[word])
        for word in words
    ]
    return CodeNamesGuesser(word_database, word_vecs, team, HintMemory[])
end

function learn_label!(mem :: HintMemory, word :: String, label :: Symbol)
    word_i = findfirst(mem.candidates) do (w,value,_)
        w == word
    end
    if word_i == nothing return end
    _,vec,_ = mem.candidates[word_i]
    mem.candidates[word_i] = word,vec,label
    while !isempty(mem.candidates) && mem.candidates[1][3] != :unknown
        if mem.candidates[1][3] == mem.team
            mem.num -= 1
        end
        deleteat!(mem.candidates, 1)
    end
end

function learn_label!(guesser :: CodeNamesGuesser, word :: String, label :: Symbol)
    word_i = findfirst(guesser.active_words) do (w,vec)
        w == word
    end
    deleteat!(guesser.active_words, word_i)
    for mem in guesser.active_hints
        learn_label!(mem, word, label)
    end
    filter!(mem -> mem.num > 0, guesser.active_hints)
end

function receive_hint!(guesser :: CodeNamesGuesser, word :: AbstractString, num :: Int)
    @assert num > 0 && num <= length(guesser.active_words)
    vec = get(guesser.word_database, word, nothing)
    if vec == nothing
        return false
    end

    evaluated_words = Tuple{String, Float64, Symbol}[
        (w, cosine_distance(v,vec), :unknown)
        for (w,v) in guesser.active_words
    ]
    sort!(evaluated_words; rev = true, by = d -> d[2])
    mem = HintMemory(num, word, evaluated_words, guesser.team)
    push!(guesser.active_hints, mem)
    return true
end

function make_guess(guesser :: CodeNamesGuesser) :: Union{Nothing,Tuple{String, Float32, String}}
    if isempty(guesser.active_hints) return end
    hint_mem = argmax(mem -> mem.candidates[1][2], guesser.active_hints)
    word, confidence, label = hint_mem.candidates[1]
    return word, confidence, hint_mem.word
end

mutable struct CodeNamesHinter
    word_database :: Dict{String, Vector{Float32}}
    active_words :: Vector{Tuple{String, Vector{Float32}, Symbol}}
    team :: Symbol
    other_team :: Symbol
    opponent_offset :: Float32
    assassin_offset :: Float32
    used_words :: Set{String}
    hint_meanings :: Vector{Tuple{String, Vector{Tuple{String, Float32, Symbol}}}}
    winner :: Symbol
end

function CodeNamesHinter(word_database::Dict{String, Vector{Float32}}, words::Vector{String}, labels::Vector{Symbol}, team::Symbol; opponent_offset = 0.1, assassin_offset = 0.2)
    @assert team in (:red, :blue)
    if team == :red
        other_team = :blue
    else
        other_team = :red
    end

    @assert length(labels) == length(words)
    @assert length(Set(words)) == length(words)
    @assert :blue in labels
    @assert :red in labels

    word_vec_labels = [
        (word, word_database[word], label)
        for (word, label) in zip(words, labels)
    ]
    used_words = Set(words)

    return CodeNamesHinter(
        word_database,
        word_vec_labels,
        team, other_team,
        opponent_offset, assassin_offset,
        used_words,
        [],
        :not_finished,
    )
end

function evaluate_hint_candidate(store_meaning, hinter::CodeNamesHinter, vec::Vector{Float32}) :: Tuple
    word_value_labels = Tuple{String, Float32, Symbol}[
        (word, cosine_distance(v,vec), label)
        for (word,v,label) in hinter.active_words
    ]
    best_opponent = maximum(word_value_labels) do (word, val, label)
        if label != hinter.other_team
            return -Inf
        end
        return val
    end
    best_assassin = maximum(word_value_labels) do (word, val, label)
        if label != :assassin
            return -Inf
        end
        return val
    end
    cutoff = max(
        best_opponent + hinter.opponent_offset,
        best_assassin + hinter.assassin_offset
    )
    filter!(word_value_labels) do (word, val, label)
        val > cutoff
    end
    sort!(word_value_labels; rev=true, by = ((word,val,label),) -> val)
    sequences = Int[0]
    while !isempty(word_value_labels) && word_value_labels[end][3] == :empty
        pop!(word_value_labels)
    end
    store_meaning(word_value_labels)
    if isempty(word_value_labels)
        return [0], 0.0
    end
    for (word, val, label) in word_value_labels
        if label == hinter.team
            sequences[end] += 1
        else
            push!(sequences, 0)
        end
    end
    return sequences, word_value_labels[end][2] - cutoff
end

evaluate_hint_candidate(hinter::CodeNamesHinter, vec :: Vector{Float32}) =
    evaluate_hint_candidate(hinter::CodeNamesHinter, vec) do word_value_labels
    end

function give_hint(hinter :: CodeNamesHinter) :: Tuple{String, Int}
    println("Thinking...")
    word, vec = argmax(ProgressBar(hinter.word_database)) do wv
        if wv.first in hinter.used_words
            [-1], 0.0
        else
            evaluate_hint_candidate(hinter, wv.second)
        end
    end
    sequences, dist = evaluate_hint_candidate(hinter, vec) do word_value_labels
        push!(hinter.hint_meanings, (word, word_value_labels))
    end
    push!(hinter.used_words, word)
    return word, sum(sequences)
end

function uncover_word!(hinter :: CodeNamesHinter, word :: String) :: Symbol
    word_i = findfirst(hinter.active_words) do (w, vec, label)
        w == word
    end
    _,_,label = hinter.active_words[word_i]
    deleteat!(hinter.active_words, word_i)
    if !any(hinter.active_words) do (word, vec, label)
        label == :red
    end
        hinter.winner = :red
    elseif !any(hinter.active_words) do (word, vec, label)
        label == :blue
    end
        hinter.winner = :blue
    end
    return label
end

remaining_words(hinter :: CodeNamesHinter) = map(wvl -> wvl[1], hinter.active_words)
remaining_words(guesser :: CodeNamesGuesser) = map(wv -> wv[1], guesser.active_words)

function explain_hints(hinter :: CodeNamesHinter)
    if isempty(hinter.hint_meanings) return end
    println()
    println("Here is how I meant it:")
    for (hinted_word, word_value_labels) in hinter.hint_meanings
        println(hinted_word, ':')
        for (word, value, label) in word_value_labels
            print("  ")
            if label == hinter.team
                print(word)
            else
                print("($word)", label)
            end
            print("   ")
            print(value)
            println()
        end
    end
end
