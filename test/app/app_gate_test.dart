/// 首启引导落点推导的回归测试。
///
/// [resolveOnboardingStep] 是整个引导流程的大脑：它决定用户看到哪一步、
/// 什么时候放行进主界面。这里守住需求里的每条规则，尤其是「用户手动退出
/// 账号后跳回第一步登录」——那条在引导已完成之后依然必须生效；唯一例外是
/// 用户自己选了「跳过登录」（guestMode），见文件末尾那一组。
library;

import 'package:cyrene_music_reborn/app/app_gate.dart';
import 'package:cyrene_music_reborn/features/onboarding/onboarding_steps.dart';
import 'package:flutter_test/flutter_test.dart';

/// 各参数默认取「全新用户」的状态，测试只覆写自己关心的那几个。
OnboardingStep? resolve({
  bool termsAccepted = false,
  bool onboardingCompleted = false,
  bool isLoggedIn = false,
  bool guestMode = false,
  bool audioSourceDone = false,
  bool styleSettingsDone = false,
}) => resolveOnboardingStep(
  termsAccepted: termsAccepted,
  onboardingCompleted: onboardingCompleted,
  isLoggedIn: isLoggedIn,
  guestMode: guestMode,
  audioSourceDone: audioSourceDone,
  styleSettingsDone: styleSettingsDone,
);

void main() {
  group('全新用户按顺序走完四步', () {
    test('第一步：什么都没做时停在协议', () {
      expect(resolve(), OnboardingStep.terms);
    });

    test('第二步：同意协议后要求登录', () {
      expect(resolve(termsAccepted: true), OnboardingStep.login);
    });

    test('第三步：登录后要求配音源', () {
      expect(
        resolve(termsAccepted: true, isLoggedIn: true),
        OnboardingStep.audioSource,
      );
    });

    test('第四步：越过音源步后进入样式设置', () {
      expect(
        resolve(termsAccepted: true, isLoggedIn: true, audioSourceDone: true),
        OnboardingStep.styleSettings,
      );
    });

    test('完成样式设置并标记完成后放行进主界面', () {
      expect(
        resolve(
          termsAccepted: true,
          isLoggedIn: true,
          audioSourceDone: true,
          styleSettingsDone: true,
        ),
        isNull,
      );
    });
  });

  group('协议是硬门槛', () {
    test('即便已登录且走完引导，未同意协议仍停在第一步', () {
      expect(
        resolve(
          isLoggedIn: true,
          audioSourceDone: true,
          styleSettingsDone: true,
        ),
        OnboardingStep.terms,
      );
    });
  });

  group('退出登录后回到第二步', () {
    test('引导已完成的老用户退出登录 → 登录步', () {
      expect(
        resolve(
          termsAccepted: true,
          onboardingCompleted: true,
          isLoggedIn: false,
        ),
        OnboardingStep.login,
      );
    });

    test('重新登录后直接回主界面，不再重走音源与样式步', () {
      expect(
        resolve(
          termsAccepted: true,
          onboardingCompleted: true,
          isLoggedIn: true,
        ),
        isNull,
      );
    });
  });

  group('老用户兼容', () {
    test('历史已完成的用户（第四步标记缺省）直接进主界面', () {
      // onboardingCompleted=true，但新加的 audioSourceDone/styleSettingsDone
      // 对老用户都是 false——不能被重新要求走一遍。
      expect(
        resolve(termsAccepted: true, onboardingCompleted: true, isLoggedIn: true),
        isNull,
      );
    });
  });

  group('跳过登录（游客模式）', () {
    test('同意协议后选了跳过登录 → 不再停在登录步，直接进音源步', () {
      expect(
        resolve(termsAccepted: true, guestMode: true),
        OnboardingStep.audioSource,
      );
    });

    test('游客走完音源与样式步 → 放行进主界面', () {
      expect(
        resolve(
          termsAccepted: true,
          guestMode: true,
          audioSourceDone: true,
          styleSettingsDone: true,
        ),
        isNull,
      );
    });

    test('跳过登录不能绕过协议，仍停在第一步', () {
      // terms 是唯一的硬门槛，游客模式对它无效。
      expect(resolve(guestMode: true), OnboardingStep.terms);
    });

    test('游客设备上报过的登录态失效也不被挡回登录页', () {
      // 曾经登录、token 过期后 expireSession 置 signedOut：开了游客模式的设备
      // 应继续留在主界面，而不是突然弹回登录步。
      expect(
        resolve(
          termsAccepted: true,
          onboardingCompleted: true,
          isLoggedIn: false,
          guestMode: true,
        ),
        isNull,
      );
    });
  });
}
