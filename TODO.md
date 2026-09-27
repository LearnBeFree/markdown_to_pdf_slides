# Backlog (agents sholud ignore for now):

Markdown normalization step in build.sh: auto-insert a blank line after mid-document `---` separators — pandoc treats `---` followed by non-blank text as a YAML metadata block and fails with "could not find expected ':'" (fixed manually for now: keep a blank line after every `---`)

system-wide notifications: conflict strted / resolved

Also I will need to find a zathura - like pdf viewer for windows. Maybe there is a more modern zathura.. or I just undermine zathura

The only thing to note is that Stevie will need to use regular links

Фокус-слайд давай сделаем как-то иначе.. мне не нравится писать typst функцию в markdown/
Какие можешь предложить варианты по оформлению в синтаксисе markdown? Чтобы это было логично и пользователь мог догадаться сам собой, ему не приходилось читать документацию.
