package main

import (
	"errors"
	"fmt"
	"io"
	"math"
	"math/rand"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// find the glide_XXXX entries in the cwd, matching:
//   - ownership of the current user
//   - containing a _GLIDE_LEASE_FILE with mtime greater than 60 minutes
//   - or if no such file exist, a ctime of more than 10 days
//   - exclude the dir of the current glidein
func FindCandidates(excludeDir string) ([]string, float64) {

	var candidates []string
	startTime := time.Now()

	now := time.Now()
	currentUser, err := user.Current()
	uid, err := strconv.Atoi(currentUser.Uid)
	if err != nil {
		fmt.Printf("GC: Error determining my own uid: %v", err)
		return candidates, time.Now().Sub(startTime).Seconds()
	}

	err = filepath.WalkDir(".", func(path string, dir os.DirEntry, err error) error {
		if err != nil {
			fmt.Printf("GC: Error accessing path %s: %v\n", path, err)
			return nil
		}

		if !dir.IsDir() {
			return nil
		}

		// to get started
		if dir.Name() == "." {
			return nil
		}

		// our own glide_ dir
		if dir.Name() == excludeDir {
			return filepath.SkipDir
		}

		// Only consider directories that match the "glide_*" pattern
		match, _ := filepath.Match("glide_*", dir.Name())
		if !match {
			return filepath.SkipDir
		}

		// glide_XXXX info
		dirInfo, err := os.Stat(dir.Name())
		if err != nil {
			fmt.Printf("GC: Error stating %s: %v\n", dir, err)
			return filepath.SkipDir
		}
		dirStat := dirInfo.Sys().(*syscall.Stat_t)

		// ignore other users' directories
		if int(dirStat.Uid) != uid {
			return filepath.SkipDir
		}

		// lease file info
		leaseFile := dir.Name() + "/_GLIDE_LEASE_FILE"
		leaseInfo, err := os.Stat(leaseFile)
		if err != nil && os.IsNotExist(err) {
			// no lease file?
			// dir older than 10 days
			if now.Sub(dirInfo.ModTime()) > 10*24*time.Hour {
				candidates = append(candidates, dir.Name())
			}
			return filepath.SkipDir
		} else if err != nil {
			fmt.Printf("GC: Error stating %s: %v\n", leaseFile, err)
			return filepath.SkipDir
		}

		// lease file older than 1 hour
		if now.Sub(leaseInfo.ModTime()) > time.Hour {
			candidates = append(candidates, dir.Name())
		}

		return filepath.SkipDir
	})

	if err != nil {
		fmt.Printf("GC: Error walking directory: %v\n", err)
	}

	return candidates, time.Now().Sub(startTime).Seconds()
}

func deleteElement(slice []string, index int) []string {
	return append(slice[:index], slice[index+1:]...)
}

// wrapper around os.Rename, with a exp backoff for some errors
func RenameWithBackoff(selectedDir, fullClaimPath string) error {

	// allow 3 attempts
	maxErrors := 3

	for try := 1; try <= maxErrors; try++ {
		err := os.Rename(selectedDir, fullClaimPath)
		if err != nil {
			fmt.Printf("GC: Unable to move directory %s: %v\n", selectedDir, err)
			switch {
			case errors.Is(err, os.ErrNotExist):
				// An error here likely means that we have a competing glidein
				// doing removals
				return err
			default:
				// other mv failures, backoff might help...
				if try == maxErrors {
					// exhausted retries
					return err
				}
				// backoff and try again
				backoff := time.Duration(math.Pow(10.0, float64(try))) * time.Second
				time.Sleep(backoff)
			}
		} else {
			// removed
			break
		}
	}
	return nil
}

// Pull out some general disk stats on the current working
// dir. Use stat (function and cli) for this data.
func diskStats() (uint64, uint64, string) {
	var stat syscall.Statfs_t
	err := syscall.Statfs(".", &stat)
	if err != nil {
		fmt.Printf("GC: Unable to stat cwd")
		return 0, 0, "n/a"
	}
	freeGBytes := stat.Bavail * uint64(stat.Bsize) / 1024 / 1024 / 1024
	totalGBytes := stat.Blocks * uint64(stat.Bsize) / 1024 / 1024 / 1024

	// call out to stat to get the nicer human readable fs type
	cmd := exec.Command("stat", "-f", "-c", "%T", ".")
	output, err := cmd.CombinedOutput()
	diskType := strings.TrimSpace(string(output))
	if err != nil {
		diskType = "n/a"
	}

	return freeGBytes, totalGBytes, diskType
}

// To publish HTCondor attributes in GWMS, we need to update two files: glidein_config and condor_vars
// https://glideinwms.fnal.gov/doc.prd/factory/custom_scripts.html
func htcondor_advertise(glidein_config, condor_vars string, reportError error,
	candidatesLastCount int, candidatesWalltime float64,
	removedCount int, removedAverage float64,
	freeGBytes uint64, totalGBytes uint64, diskType string, walltime float64) {

	gconf, err := os.OpenFile(glidein_config, os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		fmt.Println(err)
		return
	}
	defer gconf.Close()

	cvars, err := os.OpenFile(condor_vars, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		fmt.Println(err)
		return
	}
	defer cvars.Close()

	if reportError != nil {
		io.WriteString(gconf, fmt.Sprintf("GCFatalError %s\n", reportError))
		io.WriteString(cvars, "GCFatalError  S  -  +  N  Y  -\n")
	}

	io.WriteString(gconf, fmt.Sprintf("GCCandidatesCount %d\n", candidatesLastCount))
	io.WriteString(cvars, "GCCandidatesCount  I  -  +  N  Y  -\n")

	io.WriteString(gconf, fmt.Sprintf("GCCandidatesWalltime %.0f\n", candidatesWalltime))
	io.WriteString(cvars, "GCCandidatesWalltime  C  -  +  N  Y  -\n")

	io.WriteString(gconf, fmt.Sprintf("GCRemovedCount %d\n", removedCount))
	io.WriteString(cvars, "GCRemovedCount  I  -  +  N  Y  -\n")

	io.WriteString(gconf, fmt.Sprintf("GCRemovedAvgWalltime %.0f\n", removedAverage))
	io.WriteString(cvars, "GCRemovedAvgWalltime  C  -  +  N  Y  -\n")

	io.WriteString(gconf, fmt.Sprintf("GCFreeGB %d\n", freeGBytes))
	io.WriteString(cvars, "GCFreeGB  I  -  +  N  Y  -\n")

	io.WriteString(gconf, fmt.Sprintf("GCTotalGB %d\n", totalGBytes))
	io.WriteString(cvars, "GCTotalGB  I  -  +  N  Y  -\n")

	io.WriteString(gconf, fmt.Sprintf("GCDiskType %s\n", diskType))
	io.WriteString(cvars, "GCDiskType  S  -  +  N  Y  -\n")

	io.WriteString(gconf, fmt.Sprintf("GCWalltime %.0f\n", walltime))
	io.WriteString(cvars, "GCWalltime  C  -  +  N  Y  -\n")
}

func main() {

	var reportError error

	startTime := time.Now()
	fmt.Printf("GC: Starting garbage collection at %s\n", startTime.Format(time.RFC1123))

	// stats
	candidatesCount := 0
	candidatesWalltime := 0.0
	removedCount := 0
	removedWalltime := 0.0

	// remember the main working dir (this glidein), but cd .. and
	// operate from there
	myFullPath, err := os.Getwd()
	if err != nil {
		fmt.Printf("Unable to get the cwd")
		return
	}
	myGlideDir := filepath.Base(myFullPath)
	os.Chdir("..")

	candidates, candidatesWalltime := FindCandidates(myGlideDir)
	candidatesCount = len(candidates)

	for len(candidates) > 0 {

		// pick a random directory to process
		index := rand.Intn(len(candidates))
		selectedDir := candidates[index]
		candidates = deleteElement(candidates, index)

		fullClaimPath := myFullPath + "/" + selectedDir

		// claim - move the candidate to our own directory
		err = RenameWithBackoff(selectedDir, fullClaimPath)
		if err != nil {
			// a failed rename (after retries) is fatal
			reportError = err
			break
		}

		// so far so good, attempt the remove
		removalStart := time.Now()
		err = os.RemoveAll(fullClaimPath)
		if err != nil {
			fmt.Printf("GC: Unable to remove directory %s: %v\n", fullClaimPath, err)
			reportError = err
			break
		}
		removedCount += 1
		removedWalltime += time.Now().Sub(removalStart).Seconds()
	}

	removedAverage := 0.0
	if removedCount > 0 {
		removedAverage = removedWalltime / float64(removedCount)
	}

	freeGBytes, totalGBytes, diskType := diskStats()
	walltime := time.Now().Sub(startTime).Seconds()

	if reportError != nil {
		fmt.Printf("GC: Fatal error: %s\n", reportError)
	}
	fmt.Printf("GC: Number of candidates: %d\n", candidatesCount)
	fmt.Printf("GC: Candidates list walltime: %.0f seconds\n", candidatesWalltime)
	fmt.Printf("GC: Directories removed: %d\n", removedCount)
	fmt.Printf("GC: Directory average removal walltime: %.0f seconds\n", removedAverage)
	fmt.Printf("GC: Glidein disk free: %d GB\n", freeGBytes)
	fmt.Printf("GC: Glidein disk total: %d GB\n", totalGBytes)
	fmt.Printf("GC: Glidein disk type: %s\n", diskType)
	fmt.Printf("GC: Garbage collection walltime: %.0f seconds\n", walltime)

	// also advertise to the HTCondor CM
	htcondor_advertise(os.Args[1], os.Args[2], reportError, candidatesCount,
		candidatesWalltime, removedCount, removedAverage,
		freeGBytes, totalGBytes, diskType, walltime)

	os.Exit(0)
}
