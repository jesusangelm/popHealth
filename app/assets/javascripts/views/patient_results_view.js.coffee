class Thorax.Views.PatientResultsLayoutView extends Thorax.LayoutView
  initialize: ->
    @views = {}
  events:
    destroyed: ->
      view.release() for population, view of @views
  changeFilter: (population) ->
    if currentView = @getView()
      currentView.retain() # don't destroy child views until the layout view is destroyed
    @views[population] ||= new Thorax.Views.PatientResultsView(population: population, query: @query, providerId: @providerId)
    @setView @views[population]
  setQuery: (query) ->
    @query = query
    views = _(@children).values()
    _(views).each (view) -> view.setQuery query


class Thorax.Views.PatientResultsView extends Thorax.View
  tagName: 'table'
  className: 'table'
  template: JST['patient_results/index']
  fetchTriggerPoint: 500 # fetch data when we're 500 pixels away from the bottom
  patientContext: (patient) ->
    _(patient.toJSON()).extend
      first: PopHealth.Helpers.maskName(patient.get('extendedData').first[0]) if patient.get('extendedData').first[0]
      @dob = ""+patient.get('extendedData').DOB.month+"/"+patient.get('extendedData').DOB.day+"/"+patient.get('extendedData').DOB.year
      last: PopHealth.Helpers.maskName(patient.get('extendedData').last) if patient.get('extendedData').last
      formatted_birthdate: @dob
      age: moment(@dob).fromNow().split(' ')[0] if patient.get('extendedData').DOB
      gender: patient.get('extendedData').gender
      mrn: PopHealth.Helpers.formatMRN(patient.get('extendedData').medical_record_number)
  events:
    rendered: ->
      $(document).on 'scroll', @scrollHandler
    destroyed: ->
      $(document).off 'scroll', @scrollHandler
      @query.off 'change', @setCollectionAndFetch
    collection:
      sync: -> @isFetching = false

  initialize: ->
    @setCollectionAndFetch = =>
      @setCollection new Thorax.Collections.PatientResults([], parent: @query, population: @population, providerId: @providerId), render: true
      @collection.fetch()
    @isFetching = false
    @scrollHandler = =>
      distanceToBottom = $(document).height() - $(window).scrollTop() - $(window).height()
      if !@isFetching and @collection?.length and @fetchTriggerPoint > distanceToBottom
        @isFetching = true
        @collection.fetchNextPage()

    @setQuery @query

  setQuery: (query) ->
    @query.off 'change', @setCollectionAndFetch
    @query = query
    @isEpisodeOfCare = @query.parent.get('episode_of_care')
    @query.on 'change', @setCollectionAndFetch
    if @query.isNew() then @query.save() else @setCollectionAndFetch()
