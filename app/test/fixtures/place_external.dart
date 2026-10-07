import 'dart:convert';

/// The `data` of [placeExternalJson].
Map<String, dynamic> externalFixture() =>
    (jsonDecode(placeExternalJson) as Map<String, dynamic>)['data'] as Map<String, dynamic>;

/// The answer recorded for the external community source's fields of a
/// place (`PlaceExternal`), shaped as `schema/lunaway.graphql` says; the
/// contract test holds it to the schema. Kept as Dart so the integration
/// tests carry it to a device. Names and texts are invented.
const placeExternalJson = '''
{
  "data": {
    "place": {
      "id": "6f1c2a3e-0b7d-4c1e-9a55-2d3e4f5a6b7c",
      "externalPhotos": [
        {
          "id": "0d4f6a1b-1111-4a2b-8c3d-000000000001",
          "sourceId": "extcom",
          "authorName": "Loutre des Landes",
          "takenAt": "2026-08-14T09:30:00Z",
          "thumbUrl": "https://api.lunaway.net/media/demo-4/thumb",
          "largeUrl": "https://api.lunaway.net/media/demo-4/large",
          "width": 1200,
          "height": 900,
          "thumbhash": null,
          "kind": "PLACE",
          "publisher": null,
          "sourceUpdatedOn": null,
          "licence": "EXT-2026-01",
          "licenceUrl": null,
          "pageUrl": null
        },
        {
          "id": "0d4f6a1b-2222-4a2b-8c3d-000000000002",
          "sourceId": "extcom",
          "authorName": null,
          "takenAt": null,
          "thumbUrl": "https://api.lunaway.net/external-photos/0d4f6a1b-2222-4a2b-8c3d-000000000002/thumb",
          "largeUrl": "https://api.lunaway.net/external-photos/0d4f6a1b-2222-4a2b-8c3d-000000000002/large",
          "width": null,
          "height": null,
          "thumbhash": null,
          "kind": "PLACE",
          "publisher": null,
          "sourceUpdatedOn": null,
          "licence": "EXT-2026-01",
          "licenceUrl": null,
          "pageUrl": null
        }
      ],
      "externalRatings": [
        {
          "sourceId": "extcom",
          "average": 3.8,
          "count": 1734
        }
      ],
      "externalReviews": {
        "nodes": [
          {
            "id": "7a000000-0000-4000-8000-000000000001",
            "sourceId": "extcom",
            "authorName": "Loutre des Landes",
            "rating": 5,
            "text": "Avis externe inventé numéro 1.",
            "lang": "fr",
            "authorVehicle": "MOTORHOME",
            "writtenAt": "2026-09-12T18:00:00Z",
            "licence": "EXT-2026-01",
            "licenceUrl": null,
            "pageUrl": null
          },
          {
            "id": "7a000000-0000-4000-8000-000000000002",
            "sourceId": "extcom",
            "authorName": "Hérisson voyageur",
            "rating": 3,
            "text": "Avis externe inventé numéro 2.",
            "lang": "fr",
            "authorVehicle": null,
            "writtenAt": "2026-09-07T12:00:00Z",
            "licence": "EXT-2026-01",
            "licenceUrl": null,
            "pageUrl": null
          },
          {
            "id": "7a000000-0000-4000-8000-000000000003",
            "sourceId": "extcom",
            "authorName": null,
            "rating": null,
            "text": "Invented external review number 3.",
            "lang": "en",
            "authorVehicle": "VAN",
            "writtenAt": "2026-09-01T08:00:00Z",
            "licence": "EXT-2026-01",
            "licenceUrl": null,
            "pageUrl": null
          }
        ],
        "endCursor": "Mw",
        "hasNextPage": true,
        "totalCount": 1734
      },
      "externalDescriptions": []
    }
  }
}''';
