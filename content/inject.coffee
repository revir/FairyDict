chrome.runtime.sendMessage {
	type: 'setting',
}, (setting)->
	mouseMoveTimer = null
	plainQuerying = null

	jQuery(document).ready ()->
		jQuery('''
			<div class="fairydict-tooltip">
				<div class="fairydict-spinner">
				  <div class="fairydict-bounce1"></div>
				  <div class="fairydict-bounce2"></div>
				  <div class="fairydict-bounce3"></div>
				</div>
				<p class="fairydict-tooltip-content">
				</p>
			</div>
				''').appendTo('body')

	setupPlainContentPosition = (e) ->
		$el = jQuery('.fairydict-tooltip')
		if $el.length && e.pageX && e.pageY
			mousex = e.pageX + 20
			mousey = e.pageY + 10
			top = mousey
			left = mousex

			rect = window.document.body.getBoundingClientRect()
			domW = window.innerWidth - rect.left
			domH = window.innerHeight - rect.top

			if domW - left < 300
				left = domW - 300
			if domH - top < 200
				top = domH - 200

			$el.css({ top, left })

	jQuery(document).mousemove (e)->
		if setting.enableSelectionOnMouseMove
			if !setting.enableSelectionSK1 or (setting.enableSelectionSK1 and utils.checkEventKey(e, setting.selectionSK1))
				handleSelectionWord(e)

	jQuery(document).mouseup (e)->
		# 对 mouseup 事件做一个延时处理，
		# 以避免取消选中后getSelection依然能获得文字。
		setTimeout (()->handleMouseUp(e)), 1

	jQuery(document).bind 'keyup', (event)->
		if utils.checkEventKey event, setting.openSK1, setting.openSK2, setting.openKey
			chrome.runtime.sendMessage({
				type: 'look up',
				means: 'keyboard',
				text: window.getSelection().toString().trim()
			})
		if event.key == "Escape"
			jQuery('.fairydict-tooltip').fadeOut().hide()
			plainQuerying = null

	jQuery(document).on 'click', '.fairydict-pron-audio', (e) ->
		e.stopPropagation()
		playAudios [jQuery(this).data('mp3')]
		return false

	handleSelectionWord = (e)->
		clearTimeout(mouseMoveTimer) if mouseMoveTimer
		mouseMoveTimer = setTimeout (()->
			word = getWordAtPoint(e.target, e.clientX, e.clientY)
			if word
				console.log(word)
				handleLookupByMouse(e)
		), (setting.selectionTimeout or 500)

	playAudios = (urls) ->
		return unless urls?.length
		audios = urls.map (url)->
			return new Audio(url)

		_play = (audio, timeout)->
			timeout ?= 0
			return jQuery.Deferred (dfd)->
				_func = ()->
					setTimeout (()->
						# console.log "play: ", audio.duration, timeout
						audio.play()
						dfd.resolve(audio.duration or 1)
					), timeout

				if audio.duration
					_func()
				else
					audio.addEventListener 'loadedmetadata', _func

		__play = (idx, timeout)->
			idx ?= 0
			if audios[idx]
				_play(audios[idx], timeout).then (duration)->
					__play(idx+1, duration*1000)

		__play()

	getWordAtPoint = (elem, x, y)->
		if elem.nodeType == elem.TEXT_NODE
			range = elem.ownerDocument.createRange()
			range.selectNodeContents(elem)
			currentPos = 0
			endPos = range.endOffset
			while currentPos+1 < endPos
				range.setStart(elem, currentPos)
				range.setEnd(elem, currentPos+1)
				if range.getBoundingClientRect().left <= x && range.getBoundingClientRect().right  >= x &&
				range.getBoundingClientRect().top  <= y && range.getBoundingClientRect().bottom >= y
					range.detach()
					sel = window.getSelection()
					sel.removeAllRanges()
					sel.addRange(range)
					sel.modify("move", "backward", "word")
					sel.collapseToStart()
					sel.modify("extend", "forward", "word")
					return sel.toString().trim()

				currentPos += 1
		else
			for el in elem.childNodes
				range = el.ownerDocument.createRange()
				range.selectNodeContents(el)
				react = range.getBoundingClientRect()
				if react.left <= x && react.right  >= x && react.top  <= y && react.bottom >= y
					range.detach()
					return getWordAtPoint el, x, y
				else
					range.detach()
		return

	handleMouseUp = (event)->
		selObj = window.getSelection()
		text = selObj.toString().trim()
		unless text
			# click inside the dict
			if jQuery('.fairydict-tooltip').has(event.target).length
				return

			jQuery('.fairydict-tooltip').fadeOut().hide()
			plainQuerying = null
			return

		# issue #4
		including = jQuery(event.target).has(selObj.focusNode).length or jQuery(event.target).is(selObj.focusNode)

		if event.which == 1 and including
			handleLookupByMouse(event)

	renderQueryResult = (res) ->
		defTpl = (def) -> "<span class='fairydict-def'> #{def} </span>"
		defsTpl = (defs) -> "<span class='fairydict-defs'> #{defs} </span>"
		posTpl = (pos) -> "<span class='fairydict-pos'> #{pos} </span>"
		contentTpl = (content) -> "<div class='fairydict-content'> #{content} </div>"
		pronTpl = (pron) -> "<span class='fairydict-pron'> #{pron} </span>"
		pronAudioTpl = (src) -> "<a class='fairydict-pron-audio' href='' data-mp3='#{src}'><i class='icon-fairydict-volume'></i></a>"
		pronsTpl = (prons) -> "<div class='fairydict-prons'> #{prons} </div>"

		html = ''
		if res?.prons
			pronHtml = ''
			pronHtml += pronTpl res.prons.ame if res.prons.ame
			pronHtml += pronAudioTpl res.prons.ameAudio if res.prons.ameAudio
			pronHtml += pronTpl res.prons.bre if res.prons.bre
			pronHtml += pronAudioTpl res.prons.breAudio if res.prons.breAudio
			html += pronsTpl pronHtml if pronHtml

		renderItem = (item) ->
			posHtml = posTpl item.pos

			defs = if Array.isArray(item.def) then item.def else [item.def]
			defsHtmls = defs.map (def) -> defTpl def

			defsHtml = defsTpl defsHtmls.join('<br>')

			html += contentTpl posHtml+defsHtml if defsHtml

		res.cn.forEach renderItem if res?.cn
		res.en.forEach renderItem if res?.en

		if html
			jQuery('.fairydict-tooltip .fairydict-spinner').hide()
			jQuery('.fairydict-tooltip .fairydict-tooltip-content').html(html)
		else
			jQuery('.fairydict-tooltip').fadeOut().hide()

		return html

	handleLookupByMouse = (event)->
		text = window.getSelection().toString().trim()
		return unless text
		return if text.split(/\s/).length > 4

		return if $('.dictionaries-tooltip').length # ignore when find Dictionaries 

		if setting.enablePlainLookup && text != plainQuerying
			if !setting.enablePlainSK1 or (setting.plainSK1 and utils.checkEventKey(event, setting.plainSK1))
				jQuery('.fairydict-tooltip').fadeIn('slow')
				jQuery('.fairydict-tooltip .fairydict-spinner').show()
				jQuery('.fairydict-tooltip .fairydict-tooltip-content').empty()

				unless plainQuerying
					setupPlainContentPosition(event)

				plainQuerying = text

				chrome.runtime.sendMessage {
					type: 'look up pain',
					means: 'mouse',
					text: text
				}, (res)->
					html = renderQueryResult res
					if !html
						plainQuerying = null

					if res.prons
						audios = []

						if res.prons.ameAudio and setting.enableAmeAudio
							audios.push res.prons.ameAudio

						if res.prons.breAudio and setting.enableBreAudio
							audios.push res.prons.breAudio

						if audios.length
							playAudios audios

		if !setting.enableMouseSK1 or (setting.mouseSK1 and utils.checkEventKey(event, setting.mouseSK1))
			chrome.runtime.sendMessage({
				type: 'look up',
				means: 'mouse',
				text: text
			})


chrome.runtime.sendMessage {
	type: 'injected',
	url: location.href
}
