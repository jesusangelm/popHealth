#= require jquery/jquery
#= require jquery_ujs
#= require jquery-ui
#= require bootstrap-datepicker/core
#= require jquery-idletimer/dist/idle-timer
#= require jquery-knob/js/jquery.knob
#= require jquery-placeholder/jquery.placeholder
#= require numeral/numeral
#= require momentjs/moment
#= require bootstrap
#= require underscore/underscore
#= require backbone/backbone
#= require handlebars
#= require thorax/thorax
#= require backbone_sync_rails
#= require d3/d3
#= require jquery-tagit/js/tag-it
#
#= require config
#= require helpers
#= require population_chart
#= require provider_chart
#= require_tree ./templates
#= require_tree ./models
#= require_tree ./views
#= require router
#= require_self
#= require dataTables/jquery.dataTables
#= require teams
#= require select2

if Config.idleTimeout.isEnabled
  $(document).idleTimer Config.idleTimeout.timer
  $(document).on 'idle.idleTimer', ->
    $.ajax
      url: '/users/sign_out'
      type: 'DELETE'
      success: (result) -> window.location.href = '/logout.html'






