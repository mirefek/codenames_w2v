include("word2vec_loader.jl")
include("code_names.jl")

if length(ARGS) != 1 || !(ARGS[] in ("red", "blue"))
    print("""
Usage: julia cn_hinter TEAM
  where TEAM is "blue" or "red"

Also fill in the table of words in ./word_table.txt
and the secret table in ./secret_table.txt
Symbols in the secret table:
  B -- blue
  R -- red
  . -- empty
  # -- assassin
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

word_database = load_data("./word2vec.bin")
word_table = load_word_table("./word_table.txt")
secret_table = load_secret_table("./secret_table.txt")

hinter = CodeNamesHinter(word_database, word_table, secret_table, team)

legend = """
Commands:
! <word>        --   uncover word <word>
?               --   get a hint
#               --   exit
"""

print(legend)
while true
    print("> ")
    if eof(stdin)
        println("Game finished prematurely")
        break
    end
    cmd = readline(stdin)
    if cmd == "#"
        println("Game finished prematurely")
        break
    elseif cmd == "?"
        word, num = give_hint(hinter)
        println("Hint: $word -- $num")
    elseif startswith(cmd, "! ")
        word = cmd[3:end]
        if word in remaining_words(hinter)
            label = uncover_word!(hinter, word)
            if label == :assassin
                println("'$word' was ASSASSIN")
                println("Game is finished")
                break
            elseif label == :red
                println("'$word' was RED")
            elseif label == :blue
                println("'$word' was BLUE")
            elseif label == :empty
                println("'$word' was EMPTY")
            end
            if hinter.winner == :red
                println("Red team WON!")
                break
            elseif hinter.winner == :blue
                println("Blue team WON!")
                break
            end
        else
            println("Word '$word' is not among the remaining words")
            println("Remaining words:")
            for word in remaining_words(hinter)
                println("  ", word)
            end
        end
    elseif !isempty(cmd)
        print(legend)
    end
end
explain_hints(hinter)
