class Thorax.Views.BaseFilterView extends Thorax.View
  setupSelect2: (elementSelector, url, placeholder) ->
    $(elementSelector).select2 {
      ajax:
        url: (params) ->
          return url + params.term
        dataType: 'json'
        delay: 500
        data: (params) ->
          return {}
        processResults: (data, params) ->
          autoData = $.map data, (item) ->
            # hack-alert: cannot find how select2 option is built, so I'm fudging it here
            id =  (if item.id then item.id else item._id)
            code =  (if item.code then item.code else "")
            return {
              text: (if item.name then item.name else item.display_name),
              id:  JSON.stringify({id: id, code: code})
            }
          return {results: autoData, pagination: {more: false}}
        cache: true
      createTag: (params) ->
# Disables new tags being allowed (we only want what's returned from the search)
        return undefined
      minimumInputLength: 2
      theme: "bootstrap"
      placeholder: placeholder
      tags: true
      minimumResultsForSearch: Infinity
      width: "100%"
    }

  setupTagIt: (elementSelector, placeholder) ->
    $(elementSelector).tagit {
      allowSpaces: true
      placeholderText: placeholder
      animate: false
      removeConfirmation: true
    }

  getSelect2Values: (elementSelector, fieldName) ->
    data = {field: fieldName, items: []}
    $(elementSelector + " option:selected").each (index, item) ->
      val=JSON.parse(item.value)
      data.items.push({id: val.id, text: item.text, code:val.code})
    return data


  getText: (elementSelector, fieldName)->
    txt = $(elementSelector).text()
    return {field: fieldName, items: if txt?.length then [txt] else []}

  getValue: (elementSelector, fieldName)->
    txt = $(elementSelector).val()
    return {field: fieldName, items: if txt?.length then [txt] else []}

  getGender: ()->
    res = {field: "genders", items: []}
    # got to be a better way to handle checkboxes
    m = $('#male')[0]
    f = $('#female')[0]
    res.items.push(m.value) if m.checked
    res.items.push(f.value) if f.checked
    return res

