// Copyright 2022 The IREE Authors
//
// Licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#include "iree/hal/drivers/local_sync/registration/driver_module.h"

#include <inttypes.h>
#include <stddef.h>

#include "iree/base/api.h"
#include "iree/hal/drivers/local_sync/sync_driver.h"
#include "iree/hal/local/loaders/registration/init.h"

#define IREE_HAL_LOCAL_SYNC_DRIVER_ID 0x53594E43u  // SYNC

static iree_status_t iree_hal_local_sync_driver_factory_enumerate(
    void* self, const iree_hal_driver_info_t** out_driver_infos,
    iree_host_size_t* out_driver_info_count) {
  static const iree_hal_driver_info_t default_driver_info = {
      .driver_id = IREE_HAL_LOCAL_SYNC_DRIVER_ID,
      .driver_name = IREE_SVL("local-sync"),
      .full_name = IREE_SVL("Local executable execution using a lightweight "
                            "inline synchronous queue"),
  };
  *out_driver_info_count = 1;
  *out_driver_infos = &default_driver_info;
  return iree_ok_status();
}

static iree_status_t iree_hal_local_sync_driver_factory_try_create(
    void* self, iree_hal_driver_id_t driver_id, iree_allocator_t host_allocator,
    iree_hal_driver_t** out_driver) {
  if (driver_id != IREE_HAL_LOCAL_SYNC_DRIVER_ID) {
    return iree_make_status(IREE_STATUS_UNAVAILABLE,
                            "no driver with ID %016" PRIu64
                            " is provided by this factory",
                            driver_id);
  }

  iree_hal_sync_device_params_t default_params;
  iree_hal_sync_device_params_initialize(&default_params);

  iree_hal_executable_loader_t* loaders[8] = {NULL};
  iree_host_size_t loader_count = 0;
  iree_status_t status = iree_hal_create_all_available_executable_loaders(
      IREE_ARRAYSIZE(loaders), &loader_count, loaders, host_allocator);

  iree_hal_allocator_t* device_allocator = NULL;
  if (iree_status_is_ok(status)) {
    status = iree_hal_allocator_create_heap(iree_make_cstring_view("local"),
                                            host_allocator, host_allocator,
                                            &device_allocator);
  }

  if (iree_status_is_ok(status)) {
    status = iree_hal_sync_driver_create(
        iree_make_cstring_view("local-sync"), &default_params, loader_count,
        loaders, device_allocator, host_allocator, out_driver);
  }

  iree_hal_allocator_release(device_allocator);
  for (iree_host_size_t i = 0; i < loader_count; ++i) {
    iree_hal_executable_loader_release(loaders[i]);
  }
  return status;
}

IREE_API_EXPORT iree_status_t iree_hal_local_sync_driver_module_register(
    iree_hal_driver_registry_t* registry) {
  static const iree_hal_driver_factory_t factory = {
      .self = NULL,
      .enumerate = iree_hal_local_sync_driver_factory_enumerate,
      .try_create = iree_hal_local_sync_driver_factory_try_create,
  };
  return iree_hal_driver_registry_register_factory(registry, &factory);
}
