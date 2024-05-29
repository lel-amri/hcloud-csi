package main

import (
	"os"

	proto "github.com/container-storage-interface/spec/lib/go/csi"
	"github.com/go-kit/log"
	"github.com/go-kit/log/level"

	"github.com/hetznercloud/csi-driver/internal/api"
	"github.com/hetznercloud/csi-driver/internal/app"
	"github.com/hetznercloud/csi-driver/internal/driver"
	"github.com/hetznercloud/csi-driver/internal/volumes"
	"github.com/hetznercloud/hcloud-go/v2/hcloud/metadata"
)

var logger log.Logger

func main() {
	logger = app.CreateLogger()

	m := app.CreateMetrics(logger)

	hcloudClient, err := app.CreateHcloudClient(m.Registry(), logger)
	if err != nil {
		level.Error(logger).Log(
			"msg", "failed to initialize hcloud client",
			"err", err,
		)
		os.Exit(1)
	}

	var location string

	if s := os.Getenv("HCLOUD_VOLUME_DEFAULT_LOCATION"); s != "" {
		location = s
	} else {
		opts := []metadata.ClientOption{metadata.WithInstrumentation(m.Registry())}
		if s := os.Getenv("HCLOUD_METADATA_ENDPOINT"); s != "" {
			opts = append(opts, metadata.WithEndpoint(s))
		}
		metadataClient := metadata.NewClient(opts...)

		if !metadataClient.IsHcloudServer() {
			level.Warn(logger).Log("msg", "Unable to connect to metadata service. "+
				"In the current configuration the controller is required to run on a Hetzner Cloud server. "+
				"You can set HCLOUD_VOLUME_DEFAULT_LOCATION if you want to run it somewhere else.")
		}

		server, err := app.GetServer(logger, hcloudClient, metadataClient)
		if err != nil {
			level.Error(logger).Log(
				"msg", "failed to fetch server",
				"err", err,
			)
			os.Exit(1)
		}

		location = server.Datacenter.Location.Name
	}

	volumeService := volumes.NewIdempotentService(
		log.With(logger, "component", "idempotent-volume-service"),
		api.NewVolumeService(
			log.With(logger, "component", "api-volume-service"),
			hcloudClient,
		),
	)
	controllerService := driver.NewControllerService(
		log.With(logger, "component", "driver-controller-service"),
		volumeService,
		location,
	)
	identityService := driver.NewIdentityService(
		log.With(logger, "component", "driver-identity-service"),
	)

	listener, err := app.CreateListener()
	if err != nil {
		level.Error(logger).Log(
			"msg", "failed to create listener",
			"err", err,
		)
		os.Exit(1)
	}

	grpcServer := app.CreateGRPCServer(logger, m.UnaryServerInterceptor())

	proto.RegisterControllerServer(grpcServer, controllerService)
	proto.RegisterIdentityServer(grpcServer, identityService)

	m.InitializeMetrics(grpcServer)

	identityService.SetReady(true)

	if err := grpcServer.Serve(listener); err != nil {
		level.Error(logger).Log(
			"msg", "grpc server failed",
			"err", err,
		)
		os.Exit(1)
	}
}
