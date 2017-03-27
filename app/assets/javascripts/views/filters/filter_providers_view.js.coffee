class Thorax.Views.FilterProviders extends Thorax.Views.BaseFilterView
  template: JST['filters/filter_providers']

  context: ->
    currentRoute = Backbone.history.fragment
    _(super).extend
      titleSize: 3
      dataSize: 9
      token: $("meta[name='csrf-token']").attr('content')
      dialogTitle:  "Provider Filter"
      isUpdate: @model?
      showLoadInformation: true
      measureTypeLabel: null
      calculationTypeLabel: null
      hqmfSetId: null
      redirectRoute: currentRoute

  events:
    'ready': 'setup'
    'click #save_and_run': 'submit'

    # there does not seem to be a providers collection in the DB
  setup: ->
    @filterProvidersDialog = @$("#filterProvidersDialog")
    @setupSelect2 "#npiTags", "api/providers/search?npi="
    @setupSelect2 "#tinTags", "api/providers/search?tin="
    @setupSelect2 "#providerTypeTags", "api/value_sets/2.16.840.1.113762.1.4.1026.23.json?search="
    @setupSelect2 "#addressTags", "api/providers/search?address="

  display: ->
    @filterProvidersDialog.modal(
      "backdrop" : "static",
      "keyboard" : true,
      "show" : true)

  submit: ->
    filter = []
    filter.push @getSelect2Values "#npiTags", "npis"
    filter.push @getSelect2Values "#tinTags", "tins"
    filter.push @getSelect2Values "#providerTypeTags", "providerTypes"
    filter.push @getSelect2Values "#addressTags", "addresses"
    @filterProvidersDialog.modal('hide')
    @trigger('filterSaved', filter)
