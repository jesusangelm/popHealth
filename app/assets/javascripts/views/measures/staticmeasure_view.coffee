class Thorax.Views.StaticmeasureView extends Thorax.View
  template: JST['measures/static']

  initialize: ->
  	@listenTo(@staticmeasure, "change", @render)
  	subId = false
  	providerId = false
  	if @subId?
   		subId: @subId
  	if @providerId?
  		providerId: @providerId

  render: ->
  	$(@el).html(@template(entries: @staticmeasure.attributes,subId: @subId, providerId: @providerId))
  	this

  scrollFunction = ->
  	if document.body.scrollTop > 20 or document.documentElement.scrollTop > 20
    	document.getElementById('gototop').style.display = 'block'
  	else
    	document.getElementById('gototop').style.display = 'none'
  	return

  topFunction: ->
  	document.body.scrollTop = 0
  	document.documentElement.scrollTop = 0
  	return

  window.onscroll = ->
  	scrollFunction()
  	return