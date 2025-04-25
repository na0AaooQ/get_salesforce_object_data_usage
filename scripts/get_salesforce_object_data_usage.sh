#!/bin/sh
 
#####
## 環境設定
BASE_DIR="."
TMP_DIR="${BASE_DIR}/tmp"
SOBJECT_LIST_TMP_FILE="${TMP_DIR}/salesforce_sobject_list.txt"
 
## 容量取得対象の日付を指定する
## Salesforceオブジェクトのレコード作成日時(CreatedDate)を指定して、その日に作成されたレコード数と容量を取得する
## デフォルトでは、実行日の1日前の日付のレコード数と容量を取得する
SF_CHECK_CREATE_DATE_RANGE_START=`date -v -1d "+%Y-%m-%d"`
SF_CHECK_CREATE_DATE_RANGE_END=`date -v -1d "+%Y-%m-%d"`

## 使用するSalesforce REST APIのバージョン
SF_API_VER="v63.0"

## 環境設定を読み込む
cd ${BASE_DIR}
if [ -f .env ] ; then
  source .env
else
  echo "環境設定ファイル [${BASE_DIR}/.env] がありません。"
  echo "環境設定ファイル [${BASE_DIR}/.env] を作成の上で、スクリプトを再実行してください。"
  echo "処理を終了します。"
  exit 1
fi

## テンポラリディレクトリ作成
mkdir -p ${TMP_DIR}

## Salesforce REST APIのアクセストークン取得
SF_API_ACCESS_TOKEN=`curl -s https://$DATABASEDOTCOM_HOST/services/oauth2/token -d "grant_type=password" -d "client_id=$DATABASEDOTCOM_CLIENT_ID" -d "client_secret=$DATABASEDOTCOM_CLIENT_SECRET" -d "username=$DATABASEDOTCOM_CLIENT_USERNAME" -d "password=$DATABASEDOTCOM_CLIENT_AUTHENTICATE_PASSWORD" | awk 'BEGIN{FS="access_token\":"}{print $2}' | awk 'BEGIN{FS=",\"instance_url\""}{print $1}' | sed -e 's/\"//g'`

## Salesforce REST APIの接続先環境のURLを取得
SF_API_INSTANCE_URL=`curl -s https://$DATABASEDOTCOM_HOST/services/oauth2/token -d "grant_type=password" -d "client_id=$DATABASEDOTCOM_CLIENT_ID" -d "client_secret=$DATABASEDOTCOM_CLIENT_SECRET" -d "username=$DATABASEDOTCOM_CLIENT_USERNAME" -d "password=$DATABASEDOTCOM_CLIENT_AUTHENTICATE_PASSWORD" | awk 'BEGIN{FS="instance_url\":"}{print $2}' | awk 'BEGIN{FS=","}{print $1}' | sed -e 's/\"//g'`
 
## Salesforceデータストレージ容量取得日
GET_STORAGE_USAGE_DATE=`date "+%Y/%m/%d"`
 
## Salesforce内のオブジェクトリストを取得
curl -s "${SF_API_INSTANCE_URL}/services/data/${SF_API_VER}/sobjects/" -H "Authorization: Bearer ${SF_API_ACCESS_TOKEN}" -H "X-PrettyPrint:1" | jq -r  '.sobjects[] | [.label, .name]|@csv' > ${SOBJECT_LIST_TMP_FILE}
 
## Salesforceのオブジェクトリストの取得に成功したかチェック
if [ -s ${SOBJECT_LIST_TMP_FILE} ] ; then
  echo "Salesforceの全オブジェクトのレコード数、CreatedDateが指定した日付範囲内のレコード数をカウントします。"
  echo "接続先のSalesforce環境URL [`echo ${SF_API_INSTANCE_URL}`]"
else
  echo "Salesforceの全オブジェクトリスト取得に失敗しました。"
  echo "処理を終了します。"
  exit 1
 fi
 
## Salesforce内のオブジェクト単位のレコード数を取得
echo "Salesforceの各オブジェクトのレコード数とデータストレージ使用量取得を開始します。[`date "+%Y/%m/%d %H:%M:%S"`]"
echo ""
 
## 出力ヘッダ
echo "データ容量取得日,SFオブジェクト表示ラベル名,SFオブジェクトのAPI参照名,SFオブジェクトの全レコード数,全レコードのデータ使用量(単位GB),CreatedDateが指定した日付範囲(`echo ${SF_CHECK_CREATE_DATE_RANGE_START} 00:00:00` から `echo ${SF_CHECK_CREATE_DATE_RANGE_END} 23:59:59`)に作成されたレコード数,CreatedDateが指定した日付のレコードのデータ使用量(単位GB)"

## 各オブジェクトのレコード数とデータストレージ使用量を取得する
while read line ; do
 
  SOBJECT_LABEL_NAME=`echo "${line}" | awk 'BEGIN{FS=","}{print $1}' | sed -e 's/"//g'`
  SOBJECT_API_NAME=`echo "${line}" | awk 'BEGIN{FS=","}{print $2}' | sed -e 's/"//g'`
 
  ## Salesforceオブジェクトの全レコード数を取得
  SOBJECT_RECORD_COUNT=`curl -s "${SF_API_INSTANCE_URL}/services/data/${SF_API_VER}/limits/recordCount/?sObjects=${SOBJECT_API_NAME}" -H "Authorization: Bearer ${SF_API_ACCESS_TOKEN}" -H "X-PrettyPrint:1" | jq -r '.sObjects[] | [.name, .count] | @csv' | grep '",' | awk 'BEGIN{FS=","}{print $2}'`
 
  ## 全レコード数が0件(空白)の場合
  if [ -z ${SOBJECT_RECORD_COUNT} ] ; then
 
    echo "${GET_STORAGE_USAGE_DATE},${SOBJECT_LABEL_NAME},${SOBJECT_API_NAME},0,0,0,0"
 
  ## 全レコード数が0件(空白)以外の場合
  else
 
    ## Salesforceオブジェクトの全レコード数 データストレージ使用量(単位: GB)
    ## 小数点分の容量を記録したいので、bcコマンドも利用して算出
    SOBJECT_RECORD_COUNT_STORAGE_USAGE=`echo "scale=2; ${SOBJECT_RECORD_COUNT}*2/1024/1024" | bc | sed -e 's/^\./0./g'`
 
    ## SalesforceオブジェクトのCreatedDateが指定した日付範囲のレコード数を取得
    SOBJECT_CREATE_DATE_RECORD_COUNT_RESULT=`curl -s "${SF_API_INSTANCE_URL}/services/data/${SF_API_VER}/query/?q=SELECT+count()+FROM+${SOBJECT_API_NAME}+WHERE+CreatedDate+>=${SF_CHECK_CREATE_DATE_RANGE_START}T00:00:00Z+AND+CreatedDate+<=${SF_CHECK_CREATE_DATE_RANGE_END}T23:59:59Z" -H "Authorization: Bearer ${SF_API_ACCESS_TOKEN}" -H "X-PrettyPrint:1" | jq -r '.'`
 
    SOBJECT_CREATE_DATE_RECORD_COUNT_CHECK=`echo ${SOBJECT_CREATE_DATE_RECORD_COUNT_RESULT} | grep "totalSize" | awk 'BEGIN{FS="totalSize"}{print $2}' | awk 'BEGIN{FS=","}{print $1}' | sed -e 's/"//g' | sed -e 's/: //g' | wc -l`
 
    if [ ${SOBJECT_CREATE_DATE_RECORD_COUNT_CHECK} -eq 1 ] ; then
 
      SOBJECT_CREATE_DATE_RECORD_COUNT=`echo ${SOBJECT_CREATE_DATE_RECORD_COUNT_RESULT} | grep "totalSize" | awk 'BEGIN{FS="totalSize"}{print $2}' | awk 'BEGIN{FS=","}{print $1}' | sed -e 's/"//g' | sed -e 's/: //g'`
 
      ## SalesforceオブジェクトのCreatedDateが指定した日付範囲のレコード数 データストレージ使用量(単位: GB)
      SOBJECT_CREATE_DATE_RECORD_COUNT_STORAGE_USAGE=`echo "scale=2; ${SOBJECT_CREATE_DATE_RECORD_COUNT}*2/1024/1024" | bc | sed -e 's/^\./0./g'`
 
    elif [ ${SOBJECT_CREATE_DATE_RECORD_COUNT_CHECK} -eq 0 ] ; then
 
      SOBJECT_CREATE_DATE_EXIST_CHECK=`echo ${SOBJECT_CREATE_DATE_RECORD_COUNT_RESULT} | grep "No such column 'CreatedDate'" | awk 'BEGIN{FS="totalSize"}{print $2}' | awk 'BEGIN{FS=","}{print $1}' | sed -e 's/"//g' | sed -e 's/: //g' | wc -l`
 
      if [ ${SOBJECT_CREATE_DATE_EXIST_CHECK} -eq 1 ] ; then
        SOBJECT_CREATE_DATE_RECORD_COUNT="取得対象外(CreatedDate項目が存在しないオブジェクト)"
        SOBJECT_CREATE_DATE_RECORD_COUNT_STORAGE_USAGE="取得対象外(CreatedDate項目が存在しないオブジェクト)"
      else
        SOBJECT_CREATE_DATE_RECORD_COUNT="0"
        SOBJECT_CREATE_DATE_RECORD_COUNT_STORAGE_USAGE="0"
      fi
 
    else
 
      SOBJECT_CREATE_DATE_RECORD_COUNT=`echo ${SOBJECT_CREATE_DATE_RECORD_COUNT_RESULT} | grep "totalSize" | awk 'BEGIN{FS="totalSize"}{print $2}' | awk 'BEGIN{FS=","}{print $1}' | sed -e 's/"//g' | sed -e 's/: //g'`
 
      ## SalesforceオブジェクトのCreatedDateが指定した日付範囲のレコード数 データストレージ使用量(単位: GB)
      SOBJECT_CREATE_DATE_RECORD_COUNT_STORAGE_USAGE=`echo "scale=2; ${SOBJECT_CREATE_DATE_RECORD_COUNT}*2/1024/1024" | bc | sed -e 's/^\./0./g'`
 
    fi
 
    echo "${GET_STORAGE_USAGE_DATE},${SOBJECT_LABEL_NAME},${SOBJECT_API_NAME},${SOBJECT_RECORD_COUNT},${SOBJECT_RECORD_COUNT_STORAGE_USAGE},${SOBJECT_CREATE_DATE_RECORD_COUNT},${SOBJECT_CREATE_DATE_RECORD_COUNT_STORAGE_USAGE}"
 
  fi
 
done < ${SOBJECT_LIST_TMP_FILE}
 
echo ""
echo "Salesforceの各オブジェクトのレコード数とデータストレージ使用量取得が完了しました。[`date "+%Y/%m/%d %H:%M:%S"`]"
