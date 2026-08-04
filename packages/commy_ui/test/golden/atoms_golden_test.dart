import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';

import '../support/commy_test_host.dart';

/// One golden per atom, in both themes.
///
/// Each frame shows the states that actually differ in paint — enabled,
/// disabled, selected, loading — because a golden of the resting state alone
/// would keep passing while every other state rotted.
void main() {
  useCommyGoldens();

  Widget row(List<Widget> children) => Wrap(
        spacing: CommySpacing.standard.s3,
        runSpacing: CommySpacing.standard.s3,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      );

  Widget column(List<Widget> children) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: CommySpacing.standard.s3,
        children: children,
      );

  goldenTest(
    'badge',
    size: const Size(360, 140),
    builder: (context) => row(const <Widget>[
      CommyBadge(label: 'Прокси', tone: CommyTone.connected),
      CommyBadge(label: 'Прямо', tone: CommyTone.idle),
      CommyBadge(label: 'Блок', tone: CommyTone.error),
      CommyBadge(label: 'Reality', icon: CommyIcons.proxy),
    ]),
  );

  goldenTest(
    'button',
    size: const Size(360, 460),
    builder: (context) => column(<Widget>[
      CommyButton(label: 'Подключиться', onPressed: () {}),
      CommyButton(
        label: 'Импортировать',
        onPressed: () {},
        variant: CommyButtonVariant.secondary,
        icon: CommyIcons.link,
      ),
      CommyButton(
        label: 'Отмена',
        onPressed: () {},
        variant: CommyButtonVariant.ghost,
      ),
      CommyButton(
        label: 'Удалить',
        onPressed: () {},
        variant: CommyButtonVariant.danger,
        icon: CommyIcons.delete,
      ),
      const CommyButton(label: 'Недоступно', onPressed: null),
      CommyButton(label: 'Обновление', onPressed: () {}, isLoading: true),
      CommyButton(label: 'Во всю ширину', onPressed: () {}, isFullWidth: true),
    ]),
  );

  goldenTest(
    'checkbox',
    size: const Size(280, 120),
    builder: (context) => row(<Widget>[
      CommyCheckbox(value: true, onChanged: (_) {}),
      CommyCheckbox(value: false, onChanged: (_) {}),
      const CommyCheckbox(value: true, onChanged: null),
      const CommyCheckbox(value: false, onChanged: null),
    ]),
  );

  goldenTest(
    'chip',
    size: const Size(360, 160),
    builder: (context) => row(<Widget>[
      CommyChip(label: 'Все', isSelected: true, onTap: () {}),
      CommyChip(label: 'Европа', onTap: () {}),
      CommyChip(label: 'VLESS', icon: CommyIcons.proxy, onTap: () {}),
      CommyChip(
        label: 'Быстрые',
        onTap: () {},
        onRemove: () {},
        removeSemanticLabel: 'Убрать фильтр',
      ),
    ]),
  );

  goldenTest(
    'divider',
    size: const Size(320, 120),
    builder: (context) => column(<Widget>[
      const SizedBox(width: 280, child: CommyDivider()),
      const SizedBox(width: 280, child: CommyDivider(isStrong: true)),
      SizedBox(
        width: 280,
        child: CommyDivider(indent: CommySpacing.standard.s8),
      ),
    ]),
  );

  goldenTest(
    'icon_button',
    size: const Size(320, 120),
    builder: (context) => row(<Widget>[
      CommyIconButton(
        icon: CommyIcons.settings,
        onPressed: () {},
        semanticLabel: 'Настройки',
      ),
      CommyIconButton(
        icon: CommyIcons.add,
        onPressed: () {},
        semanticLabel: 'Добавить',
      ),
      CommyIconButton(
        icon: CommyIcons.refresh,
        onPressed: () {},
        semanticLabel: 'Обновить',
        isSelected: true,
      ),
      const CommyIconButton(
        icon: CommyIcons.delete,
        onPressed: null,
        semanticLabel: 'Удалить',
      ),
    ]),
  );

  goldenTest(
    'radio',
    size: const Size(280, 120),
    builder: (context) => row(<Widget>[
      CommyRadio<int>(value: 1, groupValue: 1, onChanged: (_) {}),
      CommyRadio<int>(value: 2, groupValue: 1, onChanged: (_) {}),
      const CommyRadio<int>(value: 3, groupValue: 3, onChanged: null),
      const CommyRadio<int>(value: 4, groupValue: 3, onChanged: null),
    ]),
  );

  goldenTest(
    'skeleton',
    size: const Size(320, 160),
    builder: (context) => column(const <Widget>[
      CommySkeleton(width: 240),
      CommySkeleton(width: 180),
      CommySkeleton(width: 120, height: CommySizes.bandHeight),
    ]),
  );

  goldenTest(
    'spinner',
    size: const Size(280, 120),
    builder: (context) => row(<Widget>[
      const CommySpinner(),
      CommySpinner(color: context.colors.statusConnected),
      const CommySpinner(size: CommySizes.iconEmpty),
    ]),
  );

  goldenTest(
    'switch',
    size: const Size(320, 120),
    builder: (context) => row(<Widget>[
      CommySwitch(value: true, onChanged: (_) {}),
      CommySwitch(value: false, onChanged: (_) {}),
      const CommySwitch(value: true, onChanged: null),
      const CommySwitch(value: false, onChanged: null),
    ]),
  );

  goldenTest(
    'text_field',
    size: const Size(360, 560),
    builder: (context) => column(const <Widget>[
      CommyTextField(labelText: 'Имя', hintText: 'Amsterdam 03'),
      CommyTextField(
        hintText: 'https://panel.example.net/sub/…',
        prefixIcon: CommyIcons.link,
        isMonospace: true,
      ),
      CommyTextField(
        labelText: 'Ссылка',
        hintText: 'vless://…',
        errorText: 'Не похоже на ссылку vless',
      ),
      CommyTextField(
        hintText: 'Выключено',
        helperText: 'Поле недоступно',
        enabled: false,
      ),
    ]),
  );
}
