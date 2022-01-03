#!/usr/bin/env bash

# Copyright 2021 VMware, Inc. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

SCRIPT=$(realpath "${BASH_SOURCE[0]}")
TESTROOT=$(dirname "$SCRIPT")
TKG=${TKG:-${TESTROOT}/../../bin/tkg-darwin-amd64}
CLUSTERCTL=${CLUSTERCTL:-~/cluster-api/bin/clusterctl}
TESTDATA=${TESTDATA:-testdata}
CASES=${CASES:-*.case}
BUILDER_IMAGE=gcr.io/eminent-nation-87317/tkg-go-ci:latest

TKG_CONFIG_DIR="/tmp/test_tkg_config_dir"
rm -rf $TKG_CONFIG_DIR
mkdir -p $TKG_CONFIG_DIR

# shellcheck source=tests/clustergen/diffcluster/helpers.sh
. "${TESTROOT}"/diffcluster/helpers.sh

generate_cluster_configurations() {
  outputdir=$1
  cd "${TESTDATA}"
  mkdir -p ${outputdir} || true
  rm -rf ${outputdir}/*

  $TKG get mc --configdir ${TKG_CONFIG_DIR}
  docker run -t --rm -v ${TKG_CONFIG_DIR}:${TKG_CONFIG_DIR} -v ${TESTROOT}:/clustergen -w /clustergen -e TKG_CONFIG_DIR=${TKG_CONFIG_DIR} ${BUILDER_IMAGE} /bin/bash -c "./gen_duplicate_bom_azure.py $TKG_CONFIG_DIR"
  RESULT=$?
  if [[ ! $RESULT -eq 0 ]]; then
    exit 1
  fi

  echo "# failed cases" >${outputdir}/failed.txt
  echo "Running $TKG config cluster ..."
  for t in $CASES; do
    cmdargs=()
    read -r -a cmdargs < <(grep EXE: "$t" | cut -d: -f2-)
    cp "$t" /tmp/test_tkg_config
    echo $TKG --file /tmp/test_tkg_config --configdir ${TKG_CONFIG_DIR} --log_file /tmp/"$t".log config cluster "${cmdargs[@]}"
    $TKG --file /tmp/test_tkg_config --configdir ${TKG_CONFIG_DIR} --log_file /tmp/"$t".log config cluster "${cmdargs[@]}" 2>/tmp/err.txt 1>/tmp/expected.yaml
    RESULT=$?
    if [[ $RESULT -eq 0 ]]; then
      echo "$t":POS >>${outputdir}/failed.txt
      # normalize should not modify the yaml node trees, so doing so before saving to expected to
      # reduce the chance of generating diffs due to template formatting differences in the future.
      normalize /tmp/expected.yaml ${outputdir}/"$t".output
      ${CLUSTERCTL} alpha generate-normalized-topology -r -f /tmp/expected.yaml > ${outputdir}/"$t".norm.output
      echo -n "$t (POS) : "
    else
      # failure to generate a working configuration can be due to a variety of reasons. They are
      # represented as a NEGative test case. The output of the failed command is captured and is part
      # of the compliance dataset.
      cp "$t" /tmp/test_tkg_config
      $TKG --file /tmp/test_tkg_config --configdir ${TKG_CONFIG_DIR} --log_file /tmp/"$t".log config cluster "${cmdargs[@]}" &>${outputdir}/"$t".output
      echo "$t":NEG >>${outputdir}/failed.txt
      echo -n "$t (NEG) : "
    fi
    echo "${cmdargs[@]}"

    if [[ $RESULT -eq 0 ]]; then
      # XXX fixup plan, hard code cluster class
      cat "$t" | perl -pe 's/--plan (\S+)/--plan $1cc/; s/_PLAN: (\S+)/_PLAN: $1cc/' > /tmp/test_tkg_config_cc
      echo "CLUSTER_CLASS: tkg-cluster-class-dev" >> /tmp/test_tkg_config_cc
      read -r -a cmdargs < <(grep EXE: /tmp/test_tkg_config_cc | cut -d: -f2-)
      echo $TKG --file /tmp/test_tkg_config_cc --configdir ${TKG_CONFIG_DIR} --log_file /tmp/"$t"_cc.log config cluster "${cmdargs[@]}"
      $TKG --file /tmp/test_tkg_config_cc --configdir ${TKG_CONFIG_DIR} --log_file /tmp/"$t"_cc.log config cluster "${cmdargs[@]}" 2>/tmp/err_cc.txt 1>/tmp/expected_cc.yaml
      #normalize_cc /tmp/expected_cc.yaml ${outputdir}/"$t".cc.output
      cp /tmp/expected_cc.yaml ${outputdir}/"$t".cc.output
      ${CLUSTERCTL} alpha generate-normalized-topology -p -f ${outputdir}/"$t".cc.output > ${outputdir}/"$t".cc.norm.output

      echo wdiff -s ${outputdir}/"$t".norm.output ${outputdir}/"$t".cc.norm.output
      wdiff -s ${outputdir}/"$t".norm.output ${outputdir}/"$t".cc.norm.output | tail -2 | head -1 > ${outputdir}/"$t".diff_stats 
      cat ${outputdir}/"$t".diff_stats 
      echo
    fi

  done
  rm -rf $HOME/.tkg/bom/bom-clustergen-*
}

compile_diff_stats() {
   echo "SAME,DELETED,CHANGED" > ${outputdir}/diff_summary.csv
   for f in ${outputdir}/*.diff_stats; do
      cat $f | perl -pe 's/^.*\D(\d+)%.*\D(\d+)%.*\D(\d+)%.*$/$1 $2 $3/' >> ${outputdir}/diff_summary.csv
   done
   cat ${outputdir}/diff_summary.csv
   # TODO: compute mean/stddev of columns
}

generate_cluster_configurations $1
compile_diff_stats $1
