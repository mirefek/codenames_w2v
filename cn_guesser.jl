include("word2vec_loader.jl")
include("code_names.jl")

if length(ARGS) != 1 || !(ARGS[] in ("red", "blue"))
    print("""
Usage: julia cn_guesser TEAM
  where TEAM is "blue" or "red"

Also fill in the table of words in ./word_table.txt
and put a word2vec database to ./word2vec.bin
""")
    exit()
end
team = if ARGS[] == "red"
    println("Playing for the Red team")
    :red
else
    println("Playing for the Blue team")
    :blue
end

word_database = load_data("word2vec.bin")
word_table = load_word_table("./word_table.txt")

guesser = CodeNamesGuesser(word_database, word_table, team)

legend = """
Commands:
!               --   make a guess
<num> <word>    --   give me a hint
B <word>        --   <word> was blue
R <word>        --   <word> was red
. <word>        --   <word> was empty
#               --   exit
"""

print(legend)
while true
    print("> ")
    if eof(stdin)
        println("Game finished")
        break
    end
    cmd = readline(stdin)
    if cmd == "#"
        println("Game finished")
        break
    elseif cmd == "!"
        guess = make_guess(guesser)
        if guess == nothing
            println("I have no idea -- pass")
        else
            word, confidence, hinted_word = guess
            println("Well, the hint '$hinted_word' was $confidence close to...")
            println("Guess: ", word)
        end
    elseif startswith(cmd, ". ") || startswith(cmd, "B ") || startswith(cmd, "R ")
        word = cmd[3:end]
        if word in remaining_words(guesser)
            label = if startswith(cmd, ". ")
                :empty
            elseif startswith(cmd, "B ")
                :blue
            elseif startswith(cmd, "R ")
                :red
            end
            learn_label!(guesser, word, label)
            label_str = if label == :empty
                "Empty"
            elseif label == :red
                "Red"
            elseif label == :blue
                "Blue"
            end
            println("OK, word '$word' was $label_str")
        else
            println("Word '$word' is not among the remaining words")
            println("Remaining words:")
            for word in remaining_words(guesser)
                println("  ", word)
            end
        end
    elseif isempty(cmd)
        continue
    else
        hint = split(cmd)
        if length(hint) != 2
            print(legend)
            continue
        end
        num, word = hint
        if !all(isdigit, num)
            print(legend)
            continue
        end
        num = parse(Int, num)
        if num == 0
            println("Unfortunatelly, I cannot handle a hint for zero words")
            continue
        end
        if receive_hint!(guesser, word, num)
            println("Interesting... I will try to find $num words related to '$word'")
        else
            println("Unfortunatelly, I don't know the word '$word'")
        end
    end
end
