import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_host.dart';

/// The lines under a field are read, so they are drawn whole.
///
/// Material cuts a helper or an error line to one line with an ellipsis
/// unless told otherwise, and the ones the app writes there are sentences:
/// the DNS sheet's warning that the system resolver would leak every name
/// ended mid-word on a phone.
void main() {
  const error = 'Системный резолвер отвечает мимо туннеля: каждое имя, '
      'которое идёт через прокси, утекло бы. Укажите адрес резолвера';
  const helper = 'Схемы: udp, tcp, tls, https, quic, h3, dhcp. Голый адрес — '
      'это обычный UDP. «local» отдаёт запрос системе.';

  RenderParagraph paragraph(WidgetTester tester, String text) =>
      tester.renderObject<RenderParagraph>(find.text(text));

  testWidgets('a long error line wraps rather than being cut', (tester) async {
    await pumpCommy(
      tester,
      size: const Size(360, 240),
      child: const CommyTextField(hintText: 'tls://1.1.1.1', errorText: error),
    );

    expect(paragraph(tester, error).didExceedMaxLines, isFalse);
  });

  testWidgets('a long helper line wraps rather than being cut', (tester) async {
    await pumpCommy(
      tester,
      size: const Size(360, 240),
      child:
          const CommyTextField(hintText: 'tls://1.1.1.1', helperText: helper),
    );

    expect(paragraph(tester, helper).didExceedMaxLines, isFalse);
  });

  testWidgets('the label above a field is the name it is announced by', (
    tester,
  ) async {
    // The backup password sheet: a label, no hint, masked, focused on open.
    final handle = tester.ensureSemantics();
    await pumpCommy(
      tester,
      size: const Size(360, 240),
      child: const CommyTextField(labelText: 'Пароль', obscureText: true),
    );

    expect(
      tester.getSemantics(find.byType(EditableText)),
      isSemantics(label: 'Пароль', isTextField: true, isObscured: true),
    );
    handle.dispose();
  });
}
