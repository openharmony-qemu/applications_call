/*
 * Copyright (c) 2026 Harmony Contrib
 * SPDX-License-Identifier: Apache-2.0
 */
import UIExtensionContentSession from '@ohos.app.ability.UIExtensionContentSession';
import ApnList from './ApnList';
import ApnDetails from './ApnDetails';

interface SystemApnNavigationParams {
  cardType: number;
}

const storage: LocalStorage = LocalStorage.getShared();

@Entry(storage)
@Component
struct SystemApnDialogPage {
  @Provide('pathInfos') pathInfos: NavPathStack = new NavPathStack();
  private session: UIExtensionContentSession = storage.get<UIExtensionContentSession>('session') as UIExtensionContentSession;
  private slotId: number = storage.get<number>('slotId') as number;
  private started: boolean = false;

  @Builder
  destination(name: string) {
    if (name === 'apnIndex') {
      ApnList({ closeDialog: () => this.session.terminateSelf() })
    } else if (name === 'apnDetails') {
      ApnDetails()
    }
  }

  build() {
    Navigation(this.pathInfos) {
    }
    .navDestination(this.destination)
    .hideNavBar(true)
    .id('system-apn-settings-navigation')
    .onAppear(() => {
      if (!this.started) {
        this.started = true;
        const parameters: SystemApnNavigationParams = { cardType: this.slotId };
        this.pathInfos.pushPathByName('apnIndex', parameters);
      }
    })
    .width('100%').height('100%')
  }
}
