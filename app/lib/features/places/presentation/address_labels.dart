import 'package:flutter/widgets.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';

/// The icon of an address of [kind], in the search and on its details.
IconData addressIcon(AddressKind kind) => switch (kind) {
  AddressKind.houseNumber => AppIcons.address,
  AddressKind.street => AppIcons.street,
  AddressKind.locality => AppIcons.locality,
  AddressKind.town || AddressKind.postcode => AppIcons.town,
  AddressKind.region => AppIcons.region,
};

/// What an address of [kind] is, in words.
String addressKindLabel(Translations t, AddressKind kind) => switch (kind) {
  AddressKind.houseNumber => t.search.addressKind.houseNumber,
  AddressKind.street => t.search.addressKind.street,
  AddressKind.locality => t.search.addressKind.locality,
  AddressKind.town => t.search.addressKind.town,
  AddressKind.postcode => t.search.addressKind.postcode,
  AddressKind.region => t.search.addressKind.region,
};

/// The name a route gives an address as its start or its end: the address
/// and its town ("94 Rue de la Paix, Lyon"), the town once ("Orange").
String addressRouteLabel(AddressMatch address) =>
    [address.name, if (address.city case final city? when city != address.name) city].join(', ');
