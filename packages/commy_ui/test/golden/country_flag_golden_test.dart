import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';

import '../support/commy_test_host.dart';

/// Every flag we draw, in one frame.
///
/// The point of photographing them together is that a flag is wrong in a way
/// no unit test can express — a band on the wrong side, a cross too thick, a
/// crescent facing the wrong way. The golden is the assertion.
void main() {
  useCommyGoldens();

  const codes = <String>[
    'NL', 'DE', 'FR', 'PL', 'LT', //
    'RU', 'LV', 'FI', 'JP', 'EU', //
    'US', 'GB', 'SE', 'NO', 'CH', //
    'TR', 'AT', 'ES', 'IT', 'ZZ', //
  ];

  goldenTest(
    'country_flag',
    size: const Size(360, 220),
    builder: (context) => Wrap(
      spacing: CommySpacing.standard.s3,
      runSpacing: CommySpacing.standard.s3,
      children: <Widget>[
        for (final code in codes) CountryFlag(countryCode: code),
      ],
    ),
  );

  // The flags described as data rather than painted by hand. A second frame
  // rather than a longer first one, so adding a country here never repaints
  // the nineteen that were already approved.
  const more = <String>[
    'CZ', 'UA', 'EE', 'HU', 'BG', 'RO', 'MD', 'LU', 'BE', //
    'IE', 'DK', 'IS', 'PT', 'GR', 'RS', 'HR', 'SK', 'SI', //
    'BY', 'CY', 'MT', 'BA', 'AM', 'GE', 'AZ', 'KZ', 'AE', //
    'IL', 'IN', 'KR', 'SG', 'ID', 'HK', 'CN', 'VN', 'TW', //
    'TH', 'CA', 'AU', 'NZ', 'BR', 'MX', 'AR', 'CL', 'ZA', //
    'NG', //
  ];

  goldenTest(
    'country_flag_more',
    size: const Size(360, 220),
    builder: (context) => Wrap(
      spacing: CommySpacing.standard.s3,
      runSpacing: CommySpacing.standard.s3,
      children: <Widget>[
        for (final code in more) CountryFlag(countryCode: code),
      ],
    ),
  );

  goldenTest(
    'country_flag_unknown',
    size: const Size(200, 100),
    builder: (context) => Row(
      mainAxisSize: MainAxisSize.min,
      spacing: CommySpacing.standard.s3,
      children: const <Widget>[
        CountryFlag(),
        CountryFlag(countryCode: ''),
        CountryFlag(countryCode: 'Netherlands'),
        // A well-formed code we have no drawing for: its letters, not a globe.
        CountryFlag(countryCode: 'xx'),
      ],
    ),
  );
}
