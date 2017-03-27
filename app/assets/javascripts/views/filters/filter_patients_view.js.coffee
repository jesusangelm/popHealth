class Thorax.Views.FilterPatients extends Thorax.Views.BaseFilterView
  template: JST['filters/filter_patients']

  context: ->
    currentRoute = Backbone.history.fragment
    _(super).extend
      titleSize: 3
      dataSize: 9
      token: $("meta[name='csrf-token']").attr('content')
      dialogTitle:  "Patient Filter"
      isUpdate: @model?
      showLoadInformation: true
      measureTypeLabel: null
      calculationTypeLabel: null
      hqmfSetId: null
      # redirectRoute: currentRoute

  events:
    'ready': 'setup'
    'click #save_and_run': 'submit'

  setup: ->
    @filterPatientsDialog = @$("#filterPatientsDialog")
    @setupSelect2 "#payerTags", "api/value_sets/2.16.840.1.114222.4.11.3591.json?search="
    @setupSelect2 "#raceTags", "api/value_sets/2.16.840.1.114222.4.11.836.json?search="
    @setupSelect2 "#ethnicityTags", "api/value_sets/2.16.840.1.114222.4.11.837.json?search="
    @setupSelect2 "#problemListTags", "api/value_sets/xxx.json?search="
    @setupTagIt "#genderTags", ""
    @setupTagIt "#ageTags", "e.g. 18-25, >=30"

  display: ->
    @filterPatientsDialog.modal(
      "backdrop" : "static",
      "keyboard" : true,
      "show" : true)

  submit: ->
    filter = []
    filter.push @getSelect2Values "#payerTags", "payers"
    filter.push @getSelect2Values "#raceTags", "races"
    filter.push @getSelect2Values "#ethnicityTags", "ethnicities"
    filter.push @getSelect2Values "#problemListTags", "problems"
    filter.push @getText "#ageTags", "age"
    filter.push @getValue "#asOfTags", "asOf"
    filter.push @getGender()
    @filterPatientsDialog.modal('hide')
    @trigger('filterSaved', filter)

  effective_date: ->
    user_date = PopHealth.currentUser.get 'effective_date'
    if user_date
      d = new Date(user_date *1000)
    else
      d = new Date();
    return $.datepicker.formatDate('mm/dd/yy', d)