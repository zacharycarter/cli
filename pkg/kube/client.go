package kube

import (
	"fmt"
	"os"
	"time"

	"github.com/spf13/cobra"
	"k8s.io/apimachinery/pkg/api/meta"
	"k8s.io/client-go/discovery"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/restmapper"
	"k8s.io/client-go/tools/clientcmd"
	cmdutil "k8s.io/kubernetes/pkg/kubectl/cmd/util"
)

func NewKubeFactory(cmd *cobra.Command) cmdutil.Factory {
	context := cmdutil.GetFlagString(cmd, "kube-context")
	return cmdutil.NewFactory(&restClientGetter{configForContext(context)})
}

func NewKubeClient(cmd *cobra.Command) (kubernetes.Interface, error) {
	context := cmdutil.GetFlagString(cmd, "kube-context")
	return getKubeClient(context)
}

// getKubeClient creates a Kubernetes config and client for a given kubeconfig context.
func getKubeClient(context string) (kubernetes.Interface, error) {
	config, err := configForContext(context).ClientConfig()
	if err != nil {
		return nil, err
	}
	client, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, fmt.Errorf("could not get Kubernetes client: %s", err)
	}
	return client, nil
}

func configForContext(context string) clientcmd.ClientConfig {
	rules := clientcmd.NewDefaultClientConfigLoadingRules()
	rules.DefaultClientConfig = &clientcmd.DefaultClientConfig

	overrides := &clientcmd.ConfigOverrides{ClusterDefaults: clientcmd.ClusterDefaults}

	if context != "" {
		overrides.CurrentContext = context
	}
	return clientcmd.NewNonInteractiveDeferredLoadingClientConfig(rules, overrides)
}

type restClientGetter struct {
	config clientcmd.ClientConfig
}

func (r *restClientGetter) ToRESTConfig() (*rest.Config, error) {
	return r.ToRawKubeConfigLoader().ClientConfig()
}

func (r *restClientGetter) ToDiscoveryClient() (discovery.CachedDiscoveryInterface, error) {
	config, err := r.ToRESTConfig()
	if err != nil {
		return nil, err
	}
	return discovery.NewCachedDiscoveryClientForConfig(config, os.TempDir(), "", 10*time.Minute)
}

func (r *restClientGetter) ToRESTMapper() (meta.RESTMapper, error) {
	client, err := r.ToDiscoveryClient()
	if err != nil {
		return nil, err
	}
	return restmapper.NewDeferredDiscoveryRESTMapper(client), nil
}

func (r *restClientGetter) ToRawKubeConfigLoader() clientcmd.ClientConfig {
	return r.config
}
