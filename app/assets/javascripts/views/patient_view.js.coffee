class Thorax.Views.PatientView extends Thorax.View
  template: JST['patients/show']
  events:
    rendered: ->
      @$('#measures').on 'show.bs.collapse hide.bs.collapse', (e) ->
        $(e.target).prev().toggleClass('active').find('.submeasure-expander .fa').toggleClass('fa-plus-square-o fa-minus-square-o')
  context: ->
    mrn = if @model.get("medical_record_number") then PopHealth.Helpers.formatMRN(String(@model.get("medical_record_number"))) else 'N/A'
    _(super).extend
      first: PopHealth.Helpers.maskName @model.get('first')
      last: PopHealth.Helpers.maskName @model.get('last')
      effective_time: formatTime @model.get('effective_time'), 'DD MMM YYYY'
      birthdate: formatTime @model.get('birthdate'), PopHealth.Helpers.maskDateFormat 'DD MMM YYYY'
      gender: if @model.get('gender') is 'M' then 'Male' else 'Female'
      race: if @model.has('race') then @model.get('race').name else 'None Provided'
      ethnicity: if @model.has('ethnicity') then @model.get('ethnicity').name else 'None Provided'
      languages: if _.isEmpty(@model.get('language_names')) then 'Not Available' else @model.get('language_names')
      provider: if @model.has('provider_name') then @model.get('provider_name') else 'Not Available'
      measures: @measures()
      mrn: mrn

  measures: ->
    measures = new Thorax.Collection
    if @model.has 'measure_results'
      resultsByMeasure = @model.get('measure_results').groupBy 'measure_id'
      for id, results of resultsByMeasure
        measure = new Thorax.Model id: id, title: results[0].get('measure_title')
        if results.length > 1
          measure.set submeasures: new Thorax.Collection({id: result.get('sub_id'), subtitle: result.get('measure_subtitle')} for result in results)
        measures.add measure
    return measures

  # Helper function for date/time conversion
  formatTime = (time, format) -> moment(time).utc().format(format) if time

class Thorax.Views.EntryView extends Thorax.View
  context: ->
    _(super).extend
      start_time: formatTime @model.get('start_time')
      end_time: formatTime @model.get('end_time') if @model.get('end_time')?
      time_format: formatTime @model.get('time')  if @model.get('time')?
      display_end_time: @model.get('end_time') and (formatTime @model.get('start_time')) isnt (formatTime @model.get('end_time'))
      entry_type: @model.entryType
      icon: @model.icon
      description: @model.get('description')?.split('(')[0]
      codes= @model.get('codes') if @model.get('codes')?
      facility= @model.get('facility').values[0] if @model.get('facility')?
      dischargedisposition= @model.get('dischargeDisposition') if @model.get('dischargeDisposition')?
      principaldiagnosis= @model.get('principalDiagnosis') if @model.get('principalDiagnosis')?
      facilitycode: facility.code.code if facility?
      facilitycodesys: facility.code.code_system if facility?
      dischargedispositioncode: dischargedisposition.code if dischargedisposition
      dischargedispositionsys: dischargedisposition.code_system if dischargedisposition
      principaldiagnosiscode: principaldiagnosis.code if principaldiagnosis
      principaldiagnosissys: principaldiagnosis.code_system if principaldiagnosis
      lengthofstay: lengthofstaycalc(facility.locationPeriodHigh,facility.locationPeriodLow) if facility?
      result= @model.get('values') if @model.get('values')?
      resultvalue: result.models[0].attributes.scalar if result?
      resultunit: result.models[0].attributes.units if result?

  # Helper function for date/time conversion
  formatTime = (time) -> moment(time).format('MMMM Do YYYY, h:mm:ss a') if time
  lengthofstaycalc = (high,low) ->
    days = moment(high).diff(moment(low), 'days')
    return days  

### Note ###
#
# If more detail needs to be added to the entries later,
# Handlebars' partial helper works for including another file.
# Problem is it doesn't take a property holding the url - it needs
# a string literal, so you have to do if this type, use this partial
#
# {{#if allergy}} {{> "patients/_allergy"}} {{/if}}
#
# Where allergy is a property in the context that is true or false based
# based on the entryType. Each type with a partial would need their own property.
