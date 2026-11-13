/*
 * Copyright (c) 2023-2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import dataShare from '@ohos.data.dataShare';
import dataSharePredicates from '@ohos.data.dataSharePredicates';
import common from '@ohos.app.ability.common';
import { MobileDataGlobalContextHelper } from './MobileDataGlobalContextHelper';
import { Constants } from './Constants';
import { ValuesBucket, ValueType } from '@ohos.data.ValuesBucket';
import { BusinessError } from '@ohos.base';
import { DetailsCommon } from './ApnDetailsCommon';
import { LogUtils } from './LogUtils';
import { DataShareEnum } from '../model/ApnData';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { Encrypted } from './Encrypted';
import { DataShareResultSet } from '@kit.ArkData';

const TAG = 'ApnDataStorageCommon';
const password = 'password';
let dataShareHelper: dataShare.DataShareHelper;

export class DataStorage {
  public preferApnCallback = (error:BusinessError, changeInfo:dataShare.ChangeInfo) => {};

  private context: Context = MobileDataGlobalContextHelper.getContext()
    .getValue<common.UIAbilityContext>(Constants.SETTINGS_ABILITY_CONTEXT);
  private uri: string = 'datashare:///com.ohos.pdpprofileability/net/pdp_profile';
  private preferApnUri: string = 'datashare:///com.ohos.pdpprofileability/net/pdp_profile/preferapn';
  private resetApnUri: string = 'datashare:///com.ohos.pdpprofileability/net/pdp_profile/reset';

  public async initData() {
    if (dataShareHelper !== undefined) {
      return;
    }
    await dataShare.createDataShareHelper(this.context, this.uri).then((data: dataShare.DataShareHelper) => {
      LogUtils.i(TAG, 'createDataShareHelper succeed, data : ' + data);
      dataShareHelper = data;
      dataShareHelper.on('dataChange', dataShare.SubscriptionType.SUBSCRIPTION_TYPE_EXACT_URI, this.preferApnUri, this.preferApnCallback);
    }).catch((err: BusinessError) => {
      LogUtils.e(TAG, `createDataShareHelper error: code: ${err.code}, message: ${err.message} `);
    })
  }

  private checkApnData(data: ValuesBucket) {
    let ipList = ['IP', 'IPV6', 'IPV4V6'];
    if (data) {
      if (data.mvno_type === '0') {
        data.mvno_type = '';
      }
      if (data.mms_ip_address === ':') {
        data.mms_ip_address = '';
      }
      if (data.proxy_ip_address === ':') {
        data.proxy_ip_address = '';
      }
      let proIndex = data.apn_protocol as number;
      let roamProIndex = data.apn_roam_protocol as number;
      data.apn_protocol = ipList[proIndex] || data.apn_protocol;
      data.apn_roam_protocol = ipList[roamProIndex] || data.apn_roam_protocol;
    }
    return data;
  }

  public async dataInsert(simId: number, common: DetailsCommon) {
    LogUtils.i(TAG, '[dataInsert common]');
    let da = new dataSharePredicates.DataSharePredicates();
    da.equalTo('profile_name', common.name.description.toString())
      .and()
      .equalTo('mccmnc', common.mccmnc)
      .and()
      .equalTo('apn', common.apn.description.toString())
      .and()
      .equalTo('apn_types', common.apnType.description.toString())
      .and()
      .equalTo('is_roaming_apn', 1)
      .and()
      .equalTo('apn_protocol', Number(common.apnProtocol.description))
      .and()
      .equalTo('apn_roam_protocol', Number(common.apnRoamingAgreement.description))
      .and()
      .equalTo('home_url', common.mmsc.description.toString())
      .and()
      .equalTo('mms_ip_address', common.mmsProxy.description + ':' + common.mmsPort.description)
      .and()
      .equalTo('proxy_ip_address', common.proxy.description + ':' + common.port.description);
    let columns = ['*'];
    const existing = await dataShareHelper.query(this.addUriParam(this.uri, 'simId', simId), da, columns);
    try {
      if (existing.rowCount > 0 && existing.goToFirstRow()) {
        const profileID = existing.getLong(DataShareEnum.profile_id);
        await this.dataUpdate(profileID, common);
      } else {
        const values = this.checkApnData(await this.initSaveData(common));
        const inserted = await dataShareHelper.insert(this.uri, values);
        if (inserted < 0) { throw new Error('Actual APN insert failed: ' + inserted); }
        LogUtils.i(TAG, 'Actual APN insert returned:' + inserted);
      }
    } finally { existing.close(); }
  }

  public async dataDelete(profileID: number): Promise<void> {
    const predicate = new dataSharePredicates.DataSharePredicates();
    predicate.equalTo('profile_id', profileID);
    const deleted = await dataShareHelper.delete(this.uri, predicate);
    if (deleted < 0) { throw new Error('Actual APN delete failed: ' + deleted); }
    LogUtils.i(TAG, 'Actual APN delete returned:' + deleted);
  }

  public async dataReset(simId: number) {
    let preferPredicates = new dataSharePredicates.DataSharePredicates();
    let preferApnData: ValuesBucket = {
      'simId': Number(simId)
    };
    LogUtils.i(TAG, '[dataReset] simId:' + simId);
    await dataShareHelper.update(
      this.resetApnUri, preferPredicates, preferApnData).then(data=>{
      LogUtils.i(TAG, 'reset succeed, data : ' + data);
    }).catch((err: BusinessError) => {
      LogUtils.e(TAG, `reset error: code: ${err.code}, message: ${err.message} `);
    })
  }

  public async dataQuery(simId: number, sql: dataSharePredicates.DataSharePredicates): Promise<DataShareResultSet> {
    let columns = ['*'];
    let da = sql;
    return await dataShareHelper.query(this.addUriParam(this.uri, 'simId', simId), da, columns);
  }

  private addUriParam(uri: string, key: string, value: ValueType): string {
    const separator = uri.includes('?') ? '&' : '?';
    return `${uri}${separator}${encodeURIComponent(key)}=${encodeURIComponent(value)}`;
  }

  public async dataUpdate(profileID: number, value: DetailsCommon): Promise<void> {
    const predicate = new dataSharePredicates.DataSharePredicates();
    predicate.equalTo('profile_id', profileID);
    const values = this.checkApnData(await this.initSaveData(value, true));
    const changed = await dataShareHelper.update(this.uri, predicate, values);
    if (changed < 0) { throw new Error('Actual APN update failed: ' + changed); }
    LogUtils.i(TAG, 'Actual APN update returned:' + changed);
  }

  public async preferApnDataUpdate(simId: number, profileId: number): Promise<void> {
    if (dataShareHelper === undefined) {
      throw new Error('Actual APN DataShare helper is unavailable');
    }
    const values: ValuesBucket = { sim_id: simId, profile_id: profileId };
    const predicates = new dataSharePredicates.DataSharePredicates();
    const changed = await dataShareHelper.update(this.preferApnUri, predicates, values);
    if (changed < 0) {
      throw new Error('Actual preferred APN update failed: ' + changed);
    }
    LogUtils.i(TAG, 'preferApnDataUpdate returned:' + changed);
  }

  public preferApnDataQuery(simId: number): Promise<number> {
    LogUtils.i(TAG, 'preferApnDataQuery');
    return new Promise<number>(async (resolve) => {
      let queryPreferApnUri = this.preferApnUri + '?Proxy=true&simId=' + simId.toString();
      let columns = ['*'];
      let predicates = new dataSharePredicates.DataSharePredicates();
      await dataShareHelper.query(queryPreferApnUri, predicates, columns).then((data) => {
        LogUtils.i(TAG, 'preferApnDataQuery, rowCount : ' + data.rowCount);
        if (data.rowCount > 0) {
          data.goToFirstRow();
          const profileId = data.getLong(data.getColumnIndex('profile_id'));
          resolve(profileId);
        } else {
          resolve(-1);
        }
        data.close();
      }).catch((err: BusinessError) => {
        LogUtils.e(TAG, `preferApnDataQuery error: code: ${err.code}, message: ${err.message} `);
        resolve(-1);
      })
    })
  }

  public async initSaveData(common: DetailsCommon, edit: boolean = false) {
    let encrypResult = common.passWord.description.toString();
    let data: ValuesBucket = {
      'profile_name': common.name.description.toString(),
      'apn': common.apn.description.toString(),
      'proxy_ip_address': common.proxy.description + ':' + common.port.description,
      'auth_user': common.userName.description.toString(),
      'auth_pwd': encrypResult,
      'home_url': common.mmsc.description.toString(),
      'mms_ip_address': common.mmsProxy.description + ':' + common.mmsPort.description,
      'mcc': common.mcc.description.toString(),
      'mnc': common.mnc.description.toString(),
      'mccmnc': common.mcc.description.toString() + common.mnc.description.toString(),
      'opkey': common.opkey,
      'auth_type': Number(common.authenticationType.description),
      'apn_types': common.apnType.description.toString(),
      'apn_protocol': Number(common.apnProtocol.description),
      'apn_roam_protocol': Number(common.apnRoamingAgreement.description),
      'is_roaming_apn': 1,
      'bearing_system_type': this.arrayToNumber(common.bearerSystem.description as number[]),
      'edited': 1,
      'server': common.server.description.toString(),
      'mvno_type': common.mvnoType.description.toString(),
      'mvno_match_data': common.mvnoValue.description.toString()
    };
    if (edit) {
      data.profile_id = Number(common.profileID);
    }
    return data;
  }

  private arrayToNumber(arr: number[]): number {
    LogUtils.i(TAG, '[numberToArray arr]' + JSON.stringify(arr));
    let bearerBitmask = 0;
    for (let i = 0; i < arr.length; i++) {
      if (arr[i] == 0) {
        bearerBitmask = 0;
        break;
      } else {
        bearerBitmask |= 1 << (arr[i] - 1);
      }
    }
    LogUtils.i(TAG, '[numberToArray bearerBitmask]' + JSON.stringify(bearerBitmask));
    return bearerBitmask;
  }
}