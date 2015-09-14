/* global $ */

(function($) {
  'use strict';

  var algolia = algoliasearch('latency', '1ac1bc6022cf1c8f567313685c1b846a');
  var $searchInput = $('#react-search-input');

  // compute facetFilters based on the navigator locale
  var facetFilters = [];
  $.each(window.navigator.languages, function(i, lang) {
    if (lang === 'zh-CN' || lang === 'ja-JP' || lang === 'ko-KR') {
      facetFilters.push('locale:' + lang);
    }
  });
  facetFilters.push('locale:en-US'); // always fallback on en-US

  function goToSuggestion(event, item) {
    $searchInput.autocomplete('val', '');
    window.location.href = item.url;
  }

   // Autocomplete dataset source
  function datasetSource(query, callback) {
    algolia.search([{
      indexName: 'reactjs',
      query: query,
      params: {
        hitsPerPage: 5,
        facetFilters: [ facetFilters ] // search only the current locale
      }
    }], function (err, data) {
      callback(formatHits(data.results[0].hits));
    });
  }

  function formatHits(hits) {
    // Flatten all hits into one array, marking the first element with `flagName`
    function flattenHits(o, flagName) {
      return $.map(o, function(hits, category) {
        hits[0][flagName] = true;
        return $.map(hits, function(hit, i) {
          return hit;
        });
      });
    }

    // Group hits by category / subcategory
    var groupedHits = {};
    $.each(hits, function(i, hit) {
      groupedHits[hit.category] = groupedHits[hit.category] || [];
      groupedHits[hit.category].push(hit);
    });
    $.each(groupedHits, function(category, list) {
      var groupedHitsBySubCategory = {};
      $.each(list, function(i, hit) {
        groupedHitsBySubCategory[hit.subcategory] = groupedHitsBySubCategory[hit.subcategory] || [];
        groupedHitsBySubCategory[hit.subcategory].push(hit);
      });
      groupedHits[category] = flattenHits(groupedHitsBySubCategory, 'isSubcategoryHeader');
    });

    // Translate hits into smaller objects to be send to the template
    groupedHits = flattenHits(groupedHits, 'isCategoryHeader');
    return $.map(groupedHits, function(hit, i) {
      return {
        isCategoryHeader: hit.isCategoryHeader,
        isSubcategoryHeader: hit.isSubcategoryHeader,
        category: hit._highlightResult.category.value,
        subcategory: hit._highlightResult.subcategory.value,
        title: hit._highlightResult.display_title.value,
        text: hit._snippetResult ? hit._snippetResult.text.value : hit.text,
        url: hit.url
      };
    });
  }

  var dataset = {
    // Disable update of the input field when using keyboard
    displayKey: function () {
      return $searchInput.val();
    },
    source: datasetSource,
    templates: {
      suggestion: function(item) {
        var html = [];
        if (item.isCategoryHeader) {
          html.push('<div class="suggestion-category">' + item.category + '</div>');
        }
        html.push('<div class="suggestion">');
        html.push('  <div class="suggestion-subcategory-main">' + (item.isSubcategoryHeader ? item.subcategory : '') + '</div>');
        html.push('  <div class="suggestion-content">');
        html.push('    <div class="suggestion-title">' + (item.title || '') + '</div>');
        html.push('    <div class="suggestion-text">' + (item.text || '') + '</div>');
        html.push('  </div>');
        html.push('</div>');
        return html.join(' ');
      }
    }
  };

  $searchInput.autocomplete({ 
    hint: false, 
    autoselect: true
  }, dataset)
    .on('autocomplete:selected', goToSuggestion);
})($);
