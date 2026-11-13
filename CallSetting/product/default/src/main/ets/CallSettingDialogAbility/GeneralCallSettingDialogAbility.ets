/*
 * Copyright (c) 2026 Harmony Contrib
 * SPDX-License-Identifier: Apache-2.0
 */
import UIExtensionAbility from '@ohos.app.ability.UIExtensionAbility';
import UIExtensionContentSession from '@ohos.app.ability.UIExtensionContentSession';
import Want from '@ohos.app.ability.Want';
import common from '@ohos.app.ability.common';
import data from '@ohos.telephony.data';
import sim from '@ohos.telephony.sim';
import { BusinessError } from '@ohos.base';
import { Constants, LogUtils, MobileDataGlobalContextHelper } from '@ohos/common/CommonIndex';

interface SystemApnSessionState {
  session: UIExtensionContentSession;
  slotId: number;
}

const TAG: string = 'GeneralCallSettingDialogAbility';

export default class GeneralCallSettingDialogAbility extends UIExtensionAbility {
  private currentSession: UIExtensionContentSession | undefined;

  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    if (this.currentSession !== undefined ||
      (want.deviceId !== undefined && want.deviceId.length > 0) ||
      want.parameters?.['dialogReason'] !== 'SYSTEM_APN_SETTINGS') {
      session.terminateSelf();
      return;
    }
    this.currentSession = session;
    this.openApnSession(want, session);
  }

  private async openApnSession(want: Want, session: UIExtensionContentSession): Promise<void> {
    try {
      const requested: number = want.parameters?.['slotId'] as number;
      const current: number = await data.getDefaultCellularDataSlotId();
      // The public native launcher promises the actual default active SIM.
      // An arbitrary direct Want must not select a different or stale slot.
      if (!Number.isInteger(requested) || requested < 0 || requested >= sim.getMaxSimCount() ||
        requested !== current || !(await sim.isSimActive(current))) {
        session.terminateSelf();
        return;
      }
      if (this.currentSession !== session) { return; }
      MobileDataGlobalContextHelper.getContext().set<common.UIExtensionContext>(
        Constants.SETTINGS_ABILITY_CONTEXT, this.context);
      const initialState: SystemApnSessionState = { session: session, slotId: current };
      const storage: LocalStorage = new LocalStorage(initialState);
      session.loadContent('pages/SystemApnDialogPage', storage);
      session.setWindowBackgroundColor('#00000000');
      LogUtils.i(TAG, `System APN modal opened slot:${current}`);
    } catch (error) {
      const actual: BusinessError = error as BusinessError;
      LogUtils.e(TAG, `System APN modal failed code:${actual.code} message:${actual.message}`);
      if (this.currentSession === session) { session.terminateSelf(); }
    }
  }

  onSessionDestroy(session: UIExtensionContentSession): void {
    if (this.currentSession === session) { this.currentSession = undefined; }
    LogUtils.i(TAG, 'System APN modal destroyed');
  }
}
