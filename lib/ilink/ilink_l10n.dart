import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;

class ILinkUiLocalizations extends p.UiLocalizations {
  ILinkUiLocalizations();

  static const delegate = _Delegate();

  @override
  String get back => '返回';
  @override
  String get cancel => '取消';
  @override
  String get clearSearch => '清除搜索';
  @override
  String get close => '关闭';
  @override
  String get copy => '复制';
  @override
  String get cut => '剪切';
  @override
  String get dialog => '对话框';
  @override
  String get hidePassword => '隐藏凭据';
  @override
  String get more => '更多';
  @override
  String get noSearchResults => '没有搜索结果';
  @override
  String get paste => '粘贴';
  @override
  String get reset => '重置';
  @override
  String get select => '选择';
  @override
  String get search => '搜索';
  @override
  String get selectAll => '全选';
  @override
  String get showLess => '收起';
  @override
  String get showMore => '展开';
  @override
  String get showPassword => '显示凭据';
  @override
  String get sort => '排序';
  @override
  String get submit => '确定';
}

class _Delegate extends LocalizationsDelegate<p.UiLocalizations> {
  const _Delegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<p.UiLocalizations> load(Locale locale) =>
      SynchronousFuture(ILinkUiLocalizations());

  @override
  bool shouldReload(_Delegate old) => false;
}
