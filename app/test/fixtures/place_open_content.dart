import 'dart:convert';

/// The `data` of [placeOpenContentJson].
Map<String, dynamic> openContentFixture() =>
    (jsonDecode(placeOpenContentJson) as Map<String, dynamic>)['data'] as Map<String, dynamic>;

/// An answer of `PlaceExternal` for a place the open sources describe: a
/// Commons photo taken nearby, a Panoramax street view, a tourist office's
/// text and a Mangrove review, shaped as `schema/lunaway.graphql` says.
/// Names, texts and pages are invented.
const placeOpenContentJson = r'''
{
  "data": {
    "place": {
      "id": "6f1c2a3e-0b7d-4c1e-9a55-2d3e4f5a6b7c",
      "externalPhotos": [
        {
          "id": "0d4f6a1b-3333-4a2b-8c3d-000000000003",
          "sourceId": "panoramax",
          "kind": "STREET_VIEW",
          "authorName": "PanierAvide",
          "publisher": "Panoramax OpenStreetMap France",
          "sourceUpdatedOn": null,
          "licence": "CC BY-SA 4.0",
          "licenceUrl": "https://creativecommons.org/licenses/by-sa/4.0/",
          "pageUrl": "https://panoramax.openstreetmap.fr/?focus=pic&pic=d8dc9efb",
          "takenAt": "2024-05-01T10:00:00Z",
          "thumbUrl": "https://api.lunaway.net/media/demo-5/thumb",
          "largeUrl": "https://api.lunaway.net/media/demo-5/large",
          "width": 1280,
          "height": 853,
          "thumbhash": null
        },
        {
          "id": "0d4f6a1b-4444-4a2b-8c3d-000000000004",
          "sourceId": "wikimedia-commons",
          "kind": "SURROUNDINGS",
          "authorName": "Pierre",
          "publisher": null,
          "sourceUpdatedOn": null,
          "licence": "CC BY-SA 4.0",
          "licenceUrl": "https://creativecommons.org/licenses/by-sa/4.0/",
          "pageUrl": "https://commons.wikimedia.org/wiki/File:Plage_invent%C3%A9e.jpg",
          "takenAt": null,
          "thumbUrl": "https://api.lunaway.net/media/demo-6/thumb",
          "largeUrl": "https://api.lunaway.net/media/demo-6/large",
          "width": 1280,
          "height": 960,
          "thumbhash": null
        }
      ],
      "externalRatings": [
        { "sourceId": "mangrove", "average": 4.0, "count": 1 }
      ],
      "externalReviews": {
        "nodes": [
          {
            "id": "7a000000-0000-4000-8000-000000000009",
            "sourceId": "mangrove",
            "authorName": "Surreality",
            "rating": 4,
            "text": "Avis ouvert inventé, au calme.",
            "lang": null,
            "authorVehicle": null,
            "writtenAt": "2026-09-20T18:00:00Z",
            "licence": "CC BY 4.0",
            "licenceUrl": "https://creativecommons.org/licenses/by/4.0/",
            "pageUrl": "https://mangrove.reviews/list?signature=abc"
          }
        ],
        "endCursor": "OQ",
        "hasNextPage": false,
        "totalCount": 1
      },
      "externalDescriptions": [
        {
          "sourceId": "datatourisme",
          "lang": "fr",
          "text": "Aire de services inventée au bord du lac\u2026",
          "title": null,
          "publisher": "Office de tourisme inventé",
          "sourceUpdatedOn": "2026-08-04",
          "licence": "Licence Ouverte 2.0",
          "licenceUrl": "https://www.etalab.gouv.fr/licence-ouverte-open-licence/",
          "pageUrl": "https://data.datatourisme.fr/23/invented"
        }
      ]
    }
  }
}''';
