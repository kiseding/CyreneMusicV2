// Material 也导出了 SearchController（search_anchor.dart），与应用自己的同名
// 控制器冲突，与 music_app_shell 一样在此隐藏 Material 那个。
import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_miuix/miuix.dart';

import '../application/audio_sources/audio_source_preferences_controller.dart';
import '../application/auth/account_session_controller.dart';
import '../application/discovery/discover_controller.dart';
import '../application/home/home_controller.dart';
import '../application/playback/playback_controller.dart';
import '../application/playlists/playlist_library_controller.dart';
import '../application/search/search_controller.dart';
import '../application/stores/onboarding_store.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/onboarding/onboarding_steps.dart';
import 'desktop/window_caption_bar.dart';
import 'music_app_shell.dart';

/// 应用入口分流：首启引导 / 主界面（对应原版 mobile_app_gate + desktop_app_gate，
/// 两端在此合一——引导页自身按宽度自适应，不需要各写一份外壳）。
///
/// 落点完全由真实状态推导（见 [resolveOnboardingStep]），不存「当前第几步」：
/// 中途被杀进程、登录态过期、事后主动退出登录，都会自动回到正确的一步，
/// 不会出现「进度记着第 3 步、实际却已登出」的错位。
///
/// 登录默认是硬门槛：用户手动退出账号后会被挡回第二步登录页。若用户在登录步
/// 主动选了「跳过登录」（[OnboardingStore.guestMode]），登录不再是门槛——游客
/// 也能一路走到主界面，只是云端歌单、评论、一起听等需要账号的功能不可用。
class AppGate extends StatefulWidget {
  const AppGate({
    super.key,
    required this.account,
    required this.audioSources,
    required this.discover,
    required this.home,
    required this.playback,
    required this.playlists,
    required this.search,
  });

  final AccountSessionController account;
  final AudioSourcePreferencesController audioSources;
  final DiscoverController discover;
  final HomeController home;
  final PlaybackController playback;
  final PlaylistLibraryController playlists;
  final SearchController search;

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      OnboardingStore.instance,
      widget.account,
      widget.audioSources,
    ]),
    builder: (context, _) {
      final onboarding = OnboardingStore.instance;
      final account = widget.account.state;

      // 会话恢复期间先不判断：restore 尚未完成时 isLoggedIn 恒为 false，
      // 直接分流会让老用户每次冷启动都先闪一下登录引导。
      if (account.status == AccountSessionStatus.initial ||
          account.status == AccountSessionStatus.restoring) {
        return const _GateSplash();
      }

      final step = resolveOnboardingStep(
        termsAccepted: onboarding.termsAccepted,
        onboardingCompleted: onboarding.completed,
        isLoggedIn: account.isLoggedIn,
        guestMode: onboarding.guestMode,
        audioSourceDone: onboarding.audioSourceDone,
        styleSettingsDone: onboarding.styleSettingsDone,
      );

      if (step == null) {
        return MusicAppShell(
          account: widget.account,
          audioSources: widget.audioSources,
          discover: widget.discover,
          home: widget.home,
          playback: widget.playback,
          playlists: widget.playlists,
          search: widget.search,
        );
      }

      return OnboardingPage(
        step: step,
        account: widget.account,
        audioSources: widget.audioSources,
        // 登录步选「跳过登录」：落盘游客标记后重算，登录不再是门槛，直接进音源步。
        onSkipLogin: () => OnboardingStore.instance.setGuestMode(true),
        onAudioSourceDone: () => OnboardingStore.instance.setAudioSourceDone(true),
        onCompleted: OnboardingStore.instance.complete,
      );
    },
  );
}

/// 由真实状态推导当前应停在哪一步；返回 null 表示引导已走完，进主界面。
///
/// 纯函数，便于单测覆盖各种组合。规则：
/// 1. 协议未同意 → 第一步。这是硬门槛，任何时候都最优先，游客模式也不例外。
/// 2. 未登录且未选过「跳过登录」→ 第二步。登录默认是硬门槛，引导完成后依然
///    生效，所以用户事后手动退出登录会跳回登录页。
/// 3. 未越过音源步 → 第三步。越过（启用音源或跳过）即进第四步样式设置。
/// 4. 未完成样式步 → 第四步。完成即整体走完引导。
///
/// [guestMode] 是设备级的「跳过登录」标记（见 [OnboardingStore.guestMode]）：
/// 置位后规则 2 不再拦人，游客可以一路进主界面；引导已完成的设备事后退出账号，
/// 也回到主界面而不是被登录页挡住。
///
/// [onboardingCompleted] 兼容老用户：历史上已走完三步引导的，直接放行进主界面，
/// 不会因为新增的第四步标记缺省（false）而被重新要求走一遍。
OnboardingStep? resolveOnboardingStep({
  required bool termsAccepted,
  required bool onboardingCompleted,
  required bool isLoggedIn,
  required bool guestMode,
  required bool audioSourceDone,
  required bool styleSettingsDone,
}) {
  if (!termsAccepted) return OnboardingStep.terms;
  if (!isLoggedIn && !guestMode) return OnboardingStep.login;
  if (onboardingCompleted) return null;
  if (!audioSourceDone) return OnboardingStep.audioSource;
  if (!styleSettingsDone) return OnboardingStep.styleSettings;
  return null;
}

/// 会话恢复期间的过渡页：只有品牌图标与转圈，不闪任何内容。
class _GateSplash extends StatelessWidget {
  const _GateSplash();

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixScaffold(
      // 与引导页同理：桌面端窗口透明，不铺底就会露出 DWM 深色背景。
      containerColor: colors.surface,
      content: (padding) => Column(
        children: [
          // 原生标题栏已隐藏，这条过渡页也得自绘一条，否则启动瞬间窗口
          // 拖不动、没有关闭按钮。移动端塌缩为零高度。
          const WindowCaptionBar(),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipPath.shape(
                    shape: const MiuixSquircleBorder(cornerRadius: 20),
                    child: Image.asset(
                      'assets/icons/new_ico_white.png',
                      width: 76,
                      height: 76,
                      cacheWidth:
                          (76 * MediaQuery.devicePixelRatioOf(context)).round(),
                    ),
                  ),
                  const SizedBox(height: 28),
                  MiuixCircularProgressIndicator(
                    size: 22,
                    strokeWidth: 2.5,
                    colors: MiuixProgressIndicatorColors(
                      foregroundColor: colors.primary,
                      disabledForegroundColor: colors.primary,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
