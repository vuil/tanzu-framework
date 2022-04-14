# Setup workload cluster on AWS using the ClusterClass mechanism
1. Checkout `cc_integ_tests` branch of `https://github.com/saimanoj01/tanzu-framework.git` repo.
2. Run `make build-install-cli-local`. This should build and install the Tanzu CLI on your machine.
3. Update ~/.config/tanzu/tkg/bom/tkg-bom-v1.6.0-zshippable.yaml.
```
tanzu-framework-management-packages:
  - version: v0.18.0-dev-13-g233a6405    
    images:
      tanzuFrameworkManagementPackageRepositoryImage:
        imagePath: packages/management/management
        imageRepository: gcr.io/eminent-nation-87317/tkg/test2/repo/management
        tag: v0.18.0-dev
```
4. Create a management-cluster on AWS. Currently we only validated the ClusterClass based workflows on AWS. `tanzu management-cluster create --ui`
5. Set kubeconfig/kubeconfig to point to the newly created management cluster.
6. Run this script - `pkg/v1/tkg/test/scripts/cc_hack.sh`.
7. Your management-cluster is now ready for you to create a workload cluster using the cluster class mechanism. Create a workload cluster. `tanzu cluster create workload -f wc_config.yaml -v 6`
8. Contents of the `wc_config.yaml` - 
```
AWS_REGION: us-east-1
AWS_SSH_KEY_NAME: <ssh key name setup on your AWS environement>
```
9. You might hit an issue with workload cluster creation and it is a known issue - https://github.com/kubernetes-sigs/cluster-api-provider-aws/issues/3399
