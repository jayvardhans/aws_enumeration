#!/usr/bin/env python3

import argparse
import json
import os
import subprocess
import sys


OUTPUT_FILE = "out.json"
WRITABLE_FILE = "bucket_writable.txt"


def run_command(command):
    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )

    return {
        "command": " ".join(command),
        "return_code": result.returncode,
        "stdout": result.stdout.strip(),
        "stderr": result.stderr.strip()
    }


def save_output(data):
    with open(OUTPUT_FILE, "w", encoding="utf-8") as file:
        json.dump(data, file, indent=4)


def main():
    parser = argparse.ArgumentParser(
        description="Check anonymous S3 bucket access."
    )
    parser.add_argument(
        "bucket_name",
        help="S3 bucket name"
    )

    args = parser.parse_args()
    bucket = args.bucket_name

    results = {
        "bucket": bucket,
        "public": False,
        "writable": False,
        "downloaded_file": None,
        "commands": []
    }

    # Check anonymous bucket listing
    list_command = [
        "aws",
        "s3",
        "ls",
        f"s3://{bucket}",
        "--no-sign-request"
    ]

    list_result = run_command(list_command)
    results["commands"].append(list_result)

    if list_result["return_code"] != 0:
        results["message"] = "Bucket is not anonymously listable."
        save_output(results)
        print(json.dumps(results, indent=4))
        return

    results["public"] = True
    print(f"[+] Bucket is public/listable: {bucket}")

    # Find the first object from the listing
    objects = []

    for line in list_result["stdout"].splitlines():
        parts = line.split(maxsplit=3)

        if len(parts) == 4:
            objects.append(parts[3])

    # Download the first object
    if objects:
        filename = objects[0]

        download_command = [
            "aws",
            "s3",
            "cp",
            f"s3://{bucket}/{filename}",
            ".",
            "--no-sign-request"
        ]

        download_result = run_command(download_command)
        results["commands"].append(download_result)

        if download_result["return_code"] == 0:
            results["downloaded_file"] = filename
            print(f"[+] Downloaded: {filename}")
        else:
            print(f"[-] Failed to download: {filename}")
    else:
        print("[-] No objects found in the bucket.")

    # Create an empty file for the anonymous write test
    with open(WRITABLE_FILE, "wb"):
        pass

    upload_command = [
        "aws",
        "s3",
        "cp",
        WRITABLE_FILE,
        f"s3://{bucket}",
        "--no-sign-request"
    ]

    upload_result = run_command(upload_command)
    results["commands"].append(upload_result)

    if upload_result["return_code"] == 0:
        results["writable"] = True
        print(f"[+] Bucket is anonymously writable: {bucket}")
    else:
        print(f"[-] Bucket is not anonymously writable: {bucket}")

    # Remove local test file
    try:
        os.remove(WRITABLE_FILE)
    except OSError:
        pass

    results["message"] = "S3 check completed."
    save_output(results)

    print("\n[+] Results saved to out.json")
    print(json.dumps(results, indent=4))


if __name__ == "__main__":
    main()
